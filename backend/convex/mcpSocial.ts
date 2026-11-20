import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, type MutationCtx, type QueryCtx } from "./_generated/server";
import { userByUuid } from "./lib/auth";
import { canAccessThread, counterpartOf, pairBlocked, richContentKind } from "./lib/messaging";
import { fail, live, RATE_WINDOW_MS, requireUser } from "./lib/mcp/db";
import { shiftEarnings } from "./lib/mcp/earnings";
import { type McpTool, tool } from "./lib/mcp/registry";
import { addDays, clockTime, endsNextDay } from "./lib/mcp/shiftTimes";
import * as specs from "./lib/mcp/social";
import { PAYROLL_REVISION } from "./lib/payrollCompatibility";
import { overtimeWeekStart } from "./lib/shared/liveActivityPay";
import { projectedRecurringShifts } from "./lib/shared/liveActivityScheduling";
import { applicableWageSnapshot, asSnapshot } from "./liveActivities";
import { liveMessagesBefore, page, sendFor } from "./messages";
import {
  removeShareFor,
  shareBetween,
  sharedSchedule,
  sharesWith,
  shareTargetFor,
  startShareFor,
  updateMyShareFor,
  updateSharerFor,
} from "./sharing";
import { getOrCreateDirectFor, inboxFor, markReadFor, threadById } from "./threads";

// The MCP friends and messages tools. Each runs for the user the OAuth token names; mcp.ts
// checks the token, the scope and the arguments first. None of these functions is public.
// Results never carry email addresses or file URLs, and leave out pairs where either
// person blocked the other, as the app does.

type Share = Doc<"shift_shares">;

const NOT_A_FRIEND = "That person isn't one of the user's friends. Use a friend_id from list_friends.";
const NO_CONVERSATION = "No conversation with that thread_id. Use list_conversations.";

/** Who someone is, as the app shows them to friends. */
async function personOf(ctx: QueryCtx, userId: string) {
  const user = await userByUuid(ctx, userId);
  const profile = await ctx.db.query("profiles").withIndex("by_uuid", (q) => q.eq("id", userId)).unique();
  return { friend_id: userId, name: user?.name ?? null, username: profile?.username ?? null };
}

const blocked = (share: Share | null | undefined) => share?.blocked_by_user_id !== undefined;

/** A friend as list_friends shows them. "me" and "my" are the user's side. */
function friendEntry(person: Awaited<ReturnType<typeof personOf>>, theirs: Share | null, mine: Share | null) {
  return {
    ...person,
    they_share_with_me:
      theirs === null
        ? null
        : {
            since: theirs.created_at,
            earnings_visible_to_me: theirs.show_earnings,
            hidden: theirs.hidden,
            notify_me_of_their_shifts: !theirs.muted,
          },
    i_share_with_them:
      mine === null
        ? null
        : { since: mine.created_at, show_my_earnings: mine.show_earnings, notify_them_of_my_shifts: !mine.owner_muted },
  };
}

/** The two shares between the user and a friend. Fails unless one exists and neither is blocked. */
async function sharesBetween(ctx: QueryCtx, userId: string, friendId: string) {
  const mine = await shareBetween(ctx, userId, friendId);
  const theirs = await shareBetween(ctx, friendId, userId);
  if ((mine === null && theirs === null) || blocked(mine) || blocked(theirs)) fail(NOT_A_FRIEND);
  return { mine, theirs };
}

/**
 * Counts a message or share invitation against the tighter cap. It runs after the write
 * in the same mutation, so a refusal undoes the write and only writes that happened count.
 */
async function countSend(ctx: MutationCtx, userId: string) {
  // mcp.consume counted this call just before, so the row exists and its window is current.
  const row = (await ctx.db.query("mcp_rate_limits").withIndex("by_user", (q) => q.eq("user_id", userId)).unique())!;
  const sends = row.sends ?? 0;
  if (sends >= specs.MAX_SENDS) {
    const seconds = Math.ceil((row.window_start + RATE_WINDOW_MS - Date.now()) / 1000);
    fail(`The user can send at most ${specs.MAX_SENDS} messages and share invitations per 10 minutes. Try again in ${seconds} seconds.`);
  }
  await ctx.db.patch(row._id, { sends: sends + 1 });
}

type Payload = Awaited<ReturnType<typeof page>>["messages"][number];

/** A shared shift card, without its owner's ids and picture. */
function sharedShift(metadata: unknown) {
  if (richContentKind(metadata) === null) return null;
  const s = (metadata as { content: { shift_snapshot: Record<string, unknown> } }).content.shift_snapshot;
  return { date: s.shift_date, start: s.start_time, end: s.end_time, job_name: s.job_name ?? null };
}

function message(m: Payload, userId: string, names: Map<string, string | null>) {
  return {
    message_id: m.id,
    sender_id: m.sender_user_id,
    sender_name: names.get(m.sender_user_id) ?? null,
    from_me: m.sender_user_id === userId,
    text: m.body,
    sent_at: m.created_at,
    edited_at: m.edited_at,
    reply_to_message_id: m.reply_to_message_id,
    attachment_kinds: m.attachments.map((a) => a.kind),
    shared_shift: sharedShift(m.metadata),
    reactions: m.reactions.map((r) => ({ emoji: r.emoji, count: r.count, mine: r.viewer_has_reacted })),
  };
}

async function namesOf(ctx: QueryCtx, userIds: string[]) {
  const ids = [...new Set(userIds)];
  return new Map(await Promise.all(ids.map(async (id) => [id, (await userByUuid(ctx, id))?.name ?? null] as const)));
}

// ---------- Reads ----------

export const listFriends = internalQuery({
  args: { user_id: v.string() },
  handler: async (ctx, { user_id }) => {
    const { incoming, outgoing } = await sharesWith(ctx, user_id);
    const theirs = new Map(incoming.map((s) => [s.owner_id, s]));
    const mine = new Map(outgoing.map((s) => [s.viewer_id, s]));
    const ids = [...new Set([...theirs.keys(), ...mine.keys()])].filter(
      (id) => !blocked(theirs.get(id)) && !blocked(mine.get(id)),
    );
    const friends = await Promise.all(
      ids.map(async (id) => friendEntry(await personOf(ctx, id), theirs.get(id) ?? null, mine.get(id) ?? null)),
    );
    const sortName = (f: (typeof friends)[number]) => (f.name ?? f.username ?? "").toLowerCase();
    return { friends: friends.sort((a, b) => sortName(a).localeCompare(sortName(b))) };
  },
});

export const friendSchedule = internalQuery({
  args: { user_id: v.string(), friend_id: v.string(), from: v.string(), to: v.string() },
  handler: async (ctx, { user_id, friend_id, from, to }) => {
    const share = await shareBetween(ctx, friend_id, user_id);
    if (share === null || blocked(share)) fail("That person doesn't share their shifts with the user. Use list_friends.");
    if (share.hidden) {
      fail("The user hid this friend's schedule. Show it again with update_sharing and hidden: false first.");
    }
    // Weekly overtime counts the shifts from the start of the week, so pricing starts there.
    const schedule = await sharedSchedule(
      ctx,
      friend_id,
      share.show_earnings,
      { from: overtimeWeekStart(from), to },
      undefined,
      PAYROLL_REVISION,
    );
    const dates: string[] = [];
    for (let date = from; date <= to; date = addDays(date, 1)) dates.push(date);
    const jobName = (jobId: string) => schedule.jobs.find((j) => j.id === jobId)?.name ?? null;
    const shifts = [
      ...schedule.shifts.filter((s) => s.shift_date >= from),
      ...projectedRecurringShifts(schedule.recurring_shifts, dates),
    ]
      .map((s) => ({
        date: s.shift_date,
        start: clockTime(s.start_time),
        end: clockTime(s.end_time),
        ends_next_day: endsNextDay(s.start_time, s.end_time),
        job_name: jobName(s.job_id),
      }))
      .sort((a, b) => a.date.localeCompare(b.date) || a.start.localeCompare(b.start));

    let earnings = null;
    if (schedule.show_earnings) {
      // The friend shares their pay, so sharedSchedule returned these same rows unblanked.
      const snapshots = live(
        await ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", friend_id)).collect(),
      ).map(asSnapshot);
      earnings = shiftEarnings({
        from,
        to,
        regular: schedule.shifts.map(({ recurring_id, recurring_anchor_weekday, ...shift }) => shift),
        recurring: schedule.recurring_shifts,
        snapshotFor: (shift) => applicableWageSnapshot(shift, snapshots),
        currencyFor: (jobId) => schedule.jobs.find((j) => j.id === jobId)?.currency ?? "NOK",
      });
    }
    return {
      friend: await personOf(ctx, friend_id),
      time_zone: schedule.owner_time_zone ?? null,
      from,
      to,
      shifts,
      earnings_shared: schedule.show_earnings,
      earnings,
    };
  },
});

export const listConversations = internalQuery({
  args: { user_id: v.string(), limit: v.optional(v.number()), after_thread_id: v.optional(v.string()) },
  handler: async (ctx, { user_id, limit, after_thread_id }) => {
    let cursor = {};
    if (after_thread_id !== undefined) {
      const after = await threadById(ctx, after_thread_id);
      if (after === null || !(await canAccessThread(ctx, after.id, user_id))) fail(NO_CONVERSATION);
      cursor = { before_last_message_at: after.last_message_at, before_thread_id: after.id };
    }
    const inbox = await inboxFor(ctx, user_id, { limit, ...cursor });
    const conversations = await Promise.all(
      inbox.threads.map(async (t) => ({
        thread_id: t.thread_id,
        kind: t.kind,
        friend: t.counterpart_user_id === null ? null : await personOf(ctx, t.counterpart_user_id),
        title: t.title,
        unread_count: t.unread_count,
        muted: t.muted,
        last_message:
          t.last_message_id === null
            ? null
            : {
                from_me: t.last_message_sender_id === user_id,
                text: t.last_message_body,
                kind: t.last_message_preview_kind,
                sent_at: t.last_message_at,
              },
      })),
    );
    return {
      conversations,
      unread_direct_messages: inbox.unread_direct_message_count,
      has_more: inbox.has_more,
      next_after_thread_id: inbox.next_cursor?.before_thread_id ?? null,
    };
  },
});

export const readConversation = internalQuery({
  args: { user_id: v.string(), thread_id: v.string(), limit: v.optional(v.number()), before_message_id: v.optional(v.string()) },
  handler: async (ctx, { user_id, thread_id, limit, before_message_id }) => {
    if (!(await canAccessThread(ctx, thread_id, user_id))) fail(NO_CONVERSATION);
    let before = null;
    if (before_message_id !== undefined) {
      const cursor = await ctx.db.query("messages").withIndex("by_uuid", (q) => q.eq("id", before_message_id)).unique();
      if (cursor === null || cursor.thread_id !== thread_id) fail("before_message_id isn't a message in this conversation.");
      before = { created_at: cursor.created_at, id: cursor.id };
    }
    const result = await page(ctx, thread_id, user_id, limit ?? 30, before);
    const names = await namesOf(ctx, result.messages.map((m) => m.sender_user_id));
    const friendId = await counterpartOf(ctx, thread_id, user_id);
    return {
      thread_id,
      friend: friendId === null ? null : await personOf(ctx, friendId),
      messages: result.messages.map((m) => message(m, user_id, names)),
      has_more: result.has_more,
      next_before_message_id: result.next_cursor?.before_message_id ?? null,
    };
  },
});

// ---------- Writes ----------

export const sendMessage = internalMutation({
  args: { user_id: v.string(), friend_id: v.string(), text: v.string(), client_id: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    await sharesBetween(ctx, user.id, args.friend_id);
    const thread = await getOrCreateDirectFor(ctx, user.id, args.friend_id);
    if (thread === null) fail(NOT_A_FRIEND);
    const clientId = args.client_id ?? crypto.randomUUID();
    // A retry with the same client_id returns the message already sent and isn't a new send.
    const retried = await ctx.db
      .query("messages")
      .withIndex("by_thread_sender_client", (q) =>
        q.eq("thread_id", thread.thread_id).eq("sender_user_id", user.id).eq("client_id", clientId),
      )
      .unique();
    const sent = await sendFor(ctx, user.id, {
      thread_id: thread.thread_id,
      client_id: clientId,
      body: args.text,
      metadata: { sent_via: "mcp" },
    });
    if (retried === null) await countSend(ctx, user.id);
    return { thread_id: thread.thread_id, message: message(sent, user.id, await namesOf(ctx, [user.id])) };
  },
});

export const markConversationRead = internalMutation({
  args: { user_id: v.string(), thread_id: v.string() },
  handler: async (ctx, { user_id, thread_id }) => {
    const user = await requireUser(ctx, user_id);
    if (!(await canAccessThread(ctx, thread_id, user.id))) fail(NO_CONVERSATION);
    const [newest] = await liveMessagesBefore(ctx, thread_id, null, 1);
    if (newest === undefined) return { thread_id, unread_count: 0 };
    const state = await markReadFor(ctx, user.id, { thread_id, through_message_id: newest.id });
    return { thread_id, unread_count: state.unread_count };
  },
});

const SHARE_REFUSED = {
  no_identifier: "username_or_email is required.",
  not_found: "No Tidex user has that username or verified email address. Check the spelling with the user.",
  self: "That is the user's own account.",
  blocked: "The user can't share shifts with this person.",
};

export const shareShifts = internalMutation({
  args: { user_id: v.string(), target_id: v.union(v.string(), v.null()), show_earnings: v.boolean() },
  handler: async (ctx, { user_id, target_id, show_earnings }) => {
    const user = await requireUser(ctx, user_id);
    const result = await startShareFor(ctx, user.id, target_id, show_earnings);
    if (!result.success && result.code !== "exists") fail(SHARE_REFUSED[result.code]);
    if (result.success) await countSend(ctx, user.id);
    const friendId = target_id!;
    return {
      already_shared: !result.success,
      friend: friendEntry(
        await personOf(ctx, friendId),
        await shareBetween(ctx, friendId, user.id),
        await shareBetween(ctx, user.id, friendId),
      ),
    };
  },
});

export const updateSharing = internalMutation({
  args: {
    user_id: v.string(),
    friend_id: v.string(),
    show_my_earnings: v.optional(v.boolean()),
    notify_them_of_my_shifts: v.optional(v.boolean()),
    hidden: v.optional(v.boolean()),
    notify_me_of_their_shifts: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const { mine, theirs } = await sharesBetween(ctx, user.id, args.friend_id);
    if (args.show_my_earnings !== undefined || args.notify_them_of_my_shifts !== undefined) {
      if (mine === null) fail("The user doesn't share their shifts with this friend. Use share_shifts_with first.");
      // A field set to undefined would be removed from the row, so only given ones are passed.
      await updateMyShareFor(ctx, user.id, {
        viewer_id: args.friend_id,
        ...(args.show_my_earnings === undefined ? {} : { show_earnings: args.show_my_earnings }),
        ...(args.notify_them_of_my_shifts === undefined ? {} : { owner_muted: !args.notify_them_of_my_shifts }),
      });
    }
    if (args.hidden !== undefined || args.notify_me_of_their_shifts !== undefined) {
      if (theirs === null) fail("This friend doesn't share their shifts with the user, so there is nothing to hide or mute.");
      await updateSharerFor(ctx, user.id, {
        owner_id: args.friend_id,
        hidden: args.hidden,
        muted: args.notify_me_of_their_shifts === undefined ? undefined : !args.notify_me_of_their_shifts,
      });
    }
    return {
      friend: friendEntry(
        await personOf(ctx, args.friend_id),
        await shareBetween(ctx, args.friend_id, user.id),
        await shareBetween(ctx, user.id, args.friend_id),
      ),
    };
  },
});

export const stopSharing = internalMutation({
  args: { user_id: v.string(), friend_id: v.string() },
  handler: async (ctx, { user_id, friend_id }) => {
    const user = await requireUser(ctx, user_id);
    // Deleting the only share of a blocked pair would lift the block, which stays in the app.
    if (await pairBlocked(ctx, user.id, friend_id)) fail(NOT_A_FRIEND);
    const share = await shareBetween(ctx, user.id, friend_id);
    if (share !== null && !(await removeShareFor(ctx, user.id, friend_id))) fail(NOT_A_FRIEND);
    return { friend_id, i_share_with_them: false };
  },
});

export const socialTools: McpTool[] = [
  tool(specs.listFriends, (ctx, user_id) => ctx.runQuery(internal.mcpSocial.listFriends, { user_id })),
  tool(specs.getFriendSchedule, (ctx, user_id, args) => ctx.runQuery(internal.mcpSocial.friendSchedule, { user_id, ...args })),
  tool(specs.listConversations, (ctx, user_id, args) => ctx.runQuery(internal.mcpSocial.listConversations, { user_id, ...args })),
  tool(specs.readConversation, (ctx, user_id, args) => ctx.runQuery(internal.mcpSocial.readConversation, { user_id, ...args })),
  tool(specs.sendMessage, (ctx, user_id, args) => ctx.runMutation(internal.mcpSocial.sendMessage, { user_id, ...args })),
  tool(specs.markConversationRead, (ctx, user_id, args) =>
    ctx.runMutation(internal.mcpSocial.markConversationRead, { user_id, ...args }),
  ),
  tool(specs.shareShiftsWith, async (ctx, user_id, args) =>
    ctx.runMutation(internal.mcpSocial.shareShifts, {
      user_id,
      target_id: await shareTargetFor(ctx, args.identifier),
      show_earnings: args.show_earnings,
    }),
  ),
  tool(specs.updateSharing, (ctx, user_id, args) => ctx.runMutation(internal.mcpSocial.updateSharing, { user_id, ...args })),
  tool(specs.stopSharing, (ctx, user_id, args) => ctx.runMutation(internal.mcpSocial.stopSharing, { user_id, ...args })),
];
