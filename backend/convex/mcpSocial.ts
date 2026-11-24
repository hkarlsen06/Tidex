import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, type MutationCtx, type QueryCtx } from "./_generated/server";
import { userByUuid } from "./lib/auth";
import { resolveDateQuery } from "./lib/mcp/args";
import { checked, fail, live, RATE_WINDOW_MS, requireUser } from "./lib/mcp/db";
import { computeShiftsWithPay, summarizeShiftsByCurrency } from "./lib/mcp/earnings";
import { localNowInTimeZone, weekdayName } from "./lib/mcp/payPeriod";
import { type McpTool, tool } from "./lib/mcp/registry";
import { addDays, clockTime, endsNextDay } from "./lib/mcp/shiftTimes";
import * as specs from "./lib/mcp/social";
import { canAccessThread, counterpartOf, pairBlocked, richContentKind } from "./lib/messaging";
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
import { getOrCreateDirectFor, inboxFor, markReadFor } from "./threads";

// The MCP friends and messages tools. Each runs for the user the OAuth token names; none of
// these functions is public. Results never include email addresses or file URLs, and exclude
// pairs where either person blocked the other.

type Share = Doc<"shift_shares">;

const NOT_A_FRIEND = "That person isn't one of the user's friends. Use list_friends.";
const NO_CONVERSATION = "No conversation with that thread_id. Use get_messages.";

async function personOf(ctx: QueryCtx, userId: string) {
  const user = await userByUuid(ctx, userId);
  const profile = await ctx.db.query("profiles").withIndex("by_uuid", (q) => q.eq("id", userId)).unique();
  return { id: userId, name: user?.name ?? null, username: profile?.username ?? null };
}

const blocked = (share: Share | null | undefined) => share?.blocked_by_user_id !== undefined;

async function directThreadState(ctx: QueryCtx, userId: string, friendId: string) {
  const [low, high] = userId < friendId ? [userId, friendId] : [friendId, userId];
  const direct = await ctx.db
    .query("direct_threads")
    .withIndex("by_pair", (q) => q.eq("user_low_id", low).eq("user_high_id", high))
    .unique();
  if (direct === null) return { thread_id: null as string | null, unread_count: 0 };
  const state = await ctx.db
    .query("thread_user_state")
    .withIndex("by_thread_user", (q) => q.eq("thread_id", direct.thread_id).eq("user_id", userId))
    .unique();
  return { thread_id: direct.thread_id, unread_count: state?.unread_count ?? 0 };
}

function friendEntry(
  person: Awaited<ReturnType<typeof personOf>>,
  theirs: Share | null,
  mine: Share | null,
  chat?: { thread_id: string | null; unread_count: number },
) {
  return {
    ...person,
    shares_with_me: theirs !== null,
    ...(theirs !== null
      ? {
          their_earnings_visible: theirs.show_earnings,
          ...(theirs.hidden ? { hidden: true } : {}),
          notify_me: !theirs.muted,
        }
      : {}),
    i_share_with_them: mine !== null,
    ...(mine !== null
      ? {
          my_earnings_visible: mine.show_earnings,
          notify_them: !mine.owner_muted,
        }
      : {}),
    ...(chat?.thread_id ? { thread_id: chat.thread_id } : {}),
    ...(chat && chat.unread_count > 0 ? { unread_count: chat.unread_count } : {}),
  };
}

/** Resolves a friend reference (ID, @username, username, or name) among unblocked friends. */
async function resolveFriendId(ctx: QueryCtx, userId: string, ref: string): Promise<string> {
  const { incoming, outgoing } = await sharesWith(ctx, userId);
  const theirs = new Map(incoming.map((s) => [s.owner_id, s]));
  const mine = new Map(outgoing.map((s) => [s.viewer_id, s]));
  const ids = [...new Set([...theirs.keys(), ...mine.keys()])].filter(
    (id) => !blocked(theirs.get(id)) && !blocked(mine.get(id)),
  );
  const trimmed = ref.trim();
  if (ids.includes(trimmed)) return trimmed;

  const people = await Promise.all(ids.map((id) => personOf(ctx, id)));
  const stripped = trimmed.replace(/^@/, "").toLowerCase();
  const byUsername = people.filter((p) => p.username?.toLowerCase() === stripped);
  if (byUsername.length === 1) return byUsername[0]!.id;

  const lower = trimmed.toLowerCase();
  const byName = people.filter((p) => p.name?.trim().toLowerCase() === lower);
  if (byName.length === 1) return byName[0]!.id;
  if (byName.length > 1) {
    const choices = byName.map((p) => `${p.name} (${p.username ? `@${p.username}, ` : ""}${p.id})`).join(", ");
    fail(`Multiple friends match "${trimmed}". Pass the exact friend ID or username: ${choices}.`);
  }
  fail(`No friend matches "${trimmed}". Use list_friends.`);
}

/** The two shares between the user and a friend. Fails unless one exists and neither is blocked. */
async function sharesBetween(ctx: QueryCtx, userId: string, friendId: string) {
  const mine = await shareBetween(ctx, userId, friendId);
  const theirs = await shareBetween(ctx, friendId, userId);
  if ((mine === null && theirs === null) || blocked(mine) || blocked(theirs)) fail(NOT_A_FRIEND);
  return { mine, theirs };
}

async function countSend(ctx: MutationCtx, userId: string) {
  const row = (await ctx.db.query("mcp_rate_limits").withIndex("by_user", (q) => q.eq("user_id", userId)).unique())!;
  const sends = row.sends ?? 0;
  if (sends >= specs.MAX_SENDS) {
    const seconds = Math.ceil((row.window_start + RATE_WINDOW_MS - Date.now()) / 1000);
    fail(`The user can send at most ${specs.MAX_SENDS} messages and share invitations per 10 minutes. Try again in ${seconds} seconds.`);
  }
  await ctx.db.patch(row._id, { sends: sends + 1 });
}

type Payload = Awaited<ReturnType<typeof page>>["messages"][number];

function sharedShift(metadata: unknown) {
  if (richContentKind(metadata) === null) return null;
  const s = (metadata as { content: { shift_snapshot: Record<string, unknown> } }).content.shift_snapshot;
  return { date: s.shift_date, start: s.start_time, end: s.end_time, job_name: s.job_name ?? null };
}

function messageOut(m: Payload, userId: string, names: Map<string, string | null>) {
  const shiftCard = sharedShift(m.metadata);
  return {
    id: m.id,
    sender_id: m.sender_user_id,
    sender_name: names.get(m.sender_user_id) ?? null,
    from_me: m.sender_user_id === userId,
    text: m.body,
    sent_at: m.created_at,
    ...(m.edited_at ? { edited_at: m.edited_at } : {}),
    ...(m.reply_to_message_id ? { reply_to_message_id: m.reply_to_message_id } : {}),
    ...(m.attachments.length > 0 ? { attachment_kinds: m.attachments.map((a) => a.kind) } : {}),
    ...(shiftCard !== null ? { shared_shift: shiftCard } : {}),
    ...(m.reactions.length > 0
      ? { reactions: m.reactions.map((r) => ({ emoji: r.emoji, count: r.count, mine: r.viewer_has_reacted })) }
      : {}),
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
      ids.map(async (id) =>
        friendEntry(await personOf(ctx, id), theirs.get(id) ?? null, mine.get(id) ?? null, await directThreadState(ctx, user_id, id)),
      ),
    );
    const sortName = (f: (typeof friends)[number]) => (f.name ?? f.username ?? "").toLowerCase();
    return { friends: friends.sort((a, b) => sortName(a).localeCompare(sortName(b))) };
  },
});

export const friendSchedule = internalQuery({
  args: {
    user_id: v.string(),
    friend: v.string(),
    month: v.optional(v.string()),
    from: v.optional(v.string()),
    to: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const friendId = await resolveFriendId(ctx, args.user_id, args.friend);
    const share = await shareBetween(ctx, friendId, args.user_id);
    if (share === null || blocked(share)) fail("That person doesn't share their shifts with the user. Use list_friends.");
    if (share.hidden) {
      fail("The user hid this friend's schedule. Show it again with update_sharing (hidden: false) first.");
    }

    const friendProfile = await ctx.db.query("profiles").withIndex("by_uuid", (q) => q.eq("id", friendId)).unique();
    const timeZone = friendProfile?.schedule_time_zone ?? "UTC";
    const { today } = localNowInTimeZone(timeZone);
    const range = checked(() => resolveDateQuery({ month: args.month, from: args.from, to: args.to }, today, "two_weeks"));

    const schedule = await sharedSchedule(
      ctx,
      friendId,
      share.show_earnings,
      { from: overtimeWeekStart(range.from), to: range.to },
      undefined,
      PAYROLL_REVISION,
    );

    if (schedule.show_earnings) {
      const [rawSnapshots, friendSettings] = await Promise.all([
        ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", friendId)).collect(),
        ctx.db.query("user_settings").withIndex("by_user_revision", (q) => q.eq("user_id", friendId)).unique(),
      ]);
      const snapshots = live(rawSnapshots).map(asSnapshot);
      const computed = computeShiftsWithPay({
        from: range.from,
        to: range.to,
        regular: schedule.shifts.map(({ recurring_id, recurring_anchor_weekday, ...shift }) => shift),
        recurring: schedule.recurring_shifts,
        jobs: schedule.jobs.map((j) => ({
          id: j.id,
          name: j.name,
          currency: j.currency,
          payroll_day: j.payroll_day ?? undefined,
          half_tax_month: (j.half_tax_month ?? undefined) as 11 | 12 | undefined,
          pay_period: j.pay_period ?? undefined,
          is_default: j.is_default,
        })),
        snapshotFor: (shift) => applicableWageSnapshot(shift, snapshots),
        fallbackPayrollDay: friendSettings?.payroll_day,
        fallbackHalfTaxMonth: friendSettings?.half_tax_month,
      });

      return {
        friend: await personOf(ctx, friendId),
        time_zone: schedule.owner_time_zone ?? null,
        from: range.from,
        to: range.to,
        earnings_shared: true,
        summary: summarizeShiftsByCurrency(computed.shifts),
        shifts: computed.shifts.map((s) => {
          const start = clockTime(s.start_time);
          const end = clockTime(s.end_time);
          return {
            date: s.shift_date,
            weekday: weekdayName(s.shift_date),
            start,
            end,
            ...(endsNextDay(start, end) ? { ends_next_day: true } : {}),
            job_name: s.job_name,
            currency: s.currency,
            duration_hours: s.duration_hours,
            paid_hours: s.paid_hours,
            ...(s.pay_set_up
              ? {
                  gross_pay: s.gross_pay,
                  net_pay: s.net_pay,
                  tax_deducted: s.tax_deducted,
                  effective_tax_percent: s.effective_tax_percent,
                  ...(s.half_tax_applied ? { half_tax_applied: true } : {}),
                  ...(s.excluded_by_overlap ? { excluded_by_overlap: true } : {}),
                }
              : { pay_set_up: false }),
          };
        }),
        ...(computed.shifts_without_pay_setup > 0 ? { shifts_without_pay_setup: computed.shifts_without_pay_setup } : {}),
      };
    }

    const dates: string[] = [];
    for (let date = range.from; date <= range.to; date = addDays(date, 1)) dates.push(date);
    const jobName = (jobId: string) => schedule.jobs.find((j) => j.id === jobId)?.name ?? null;
    const shifts = [
      ...schedule.shifts.filter((s) => s.shift_date >= range.from),
      ...projectedRecurringShifts(schedule.recurring_shifts, dates),
    ]
      .map((s) => {
        const start = clockTime(s.start_time);
        const end = clockTime(s.end_time);
        return {
          date: s.shift_date,
          weekday: weekdayName(s.shift_date),
          start,
          end,
          ...(endsNextDay(start, end) ? { ends_next_day: true } : {}),
          job_name: jobName(s.job_id),
        };
      })
      .sort((a, b) => a.date.localeCompare(b.date) || a.start.localeCompare(b.start));

    return {
      friend: await personOf(ctx, friendId),
      time_zone: schedule.owner_time_zone ?? null,
      from: range.from,
      to: range.to,
      earnings_shared: false,
      shifts,
    };
  },
});

export const listConversations = internalQuery({
  args: {
    user_id: v.string(),
    limit: v.optional(v.number()),
    cursor: v.optional(v.object({ before_last_message_at: v.optional(v.string()), before_thread_id: v.string() })),
  },
  handler: async (ctx, { user_id, limit, cursor }) => {
    const inbox = await inboxFor(ctx, user_id, { limit, ...cursor });
    const conversations = await Promise.all(
      inbox.threads.map(async (t) => ({
        thread_id: t.thread_id,
        kind: t.kind,
        friend: t.counterpart_user_id === null ? null : await personOf(ctx, t.counterpart_user_id),
        ...(t.title ? { title: t.title } : {}),
        unread_count: t.unread_count,
        ...(t.muted ? { muted: true } : {}),
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
      unread_total: inbox.unread_direct_message_count,
      has_more: inbox.has_more,
      ...(inbox.next_cursor ? { next_cursor: specs.conversationCursor(inbox.next_cursor) } : {}),
    };
  },
});

export const readConversation = internalQuery({
  args: {
    user_id: v.string(),
    friend: v.optional(v.string()),
    thread_id: v.optional(v.string()),
    limit: v.optional(v.number()),
    before_message_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    let threadId = args.thread_id;
    let friendId: string | null = null;

    if (args.friend !== undefined) {
      friendId = await resolveFriendId(ctx, args.user_id, args.friend);
      const chat = await directThreadState(ctx, args.user_id, friendId);
      if (chat.thread_id === null) {
        return {
          thread_id: null,
          friend: await personOf(ctx, friendId),
          messages: [],
          has_more: false,
        };
      }
      threadId = chat.thread_id;
    } else {
      if (threadId === undefined || !(await canAccessThread(ctx, threadId, args.user_id))) fail(NO_CONVERSATION);
      friendId = await counterpartOf(ctx, threadId, args.user_id);
    }

    let before = null;
    if (args.before_message_id !== undefined) {
      const cursor = await ctx.db.query("messages").withIndex("by_uuid", (q) => q.eq("id", args.before_message_id!)).unique();
      if (cursor === null || cursor.thread_id !== threadId) fail("before_message_id isn't a message in this conversation.");
      before = { created_at: cursor.created_at, id: cursor.id };
    }
    const result = await page(ctx, threadId, args.user_id, args.limit ?? 30, before);
    const names = await namesOf(ctx, result.messages.map((m) => m.sender_user_id));
    return {
      thread_id: threadId,
      friend: friendId === null ? null : await personOf(ctx, friendId),
      messages: result.messages.map((m) => messageOut(m, args.user_id, names)),
      has_more: result.has_more,
      ...(result.next_cursor?.before_message_id ? { next_before_message_id: result.next_cursor.before_message_id } : {}),
    };
  },
});

// ---------- Writes ----------

export const sendMessage = internalMutation({
  args: {
    user_id: v.string(),
    friend: v.optional(v.string()),
    thread_id: v.optional(v.string()),
    text: v.string(),
    client_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    let friendId: string;
    if (args.friend !== undefined) {
      friendId = await resolveFriendId(ctx, user.id, args.friend);
    } else {
      if (args.thread_id === undefined || !(await canAccessThread(ctx, args.thread_id, user.id))) fail(NO_CONVERSATION);
      const counterpart = await counterpartOf(ctx, args.thread_id, user.id);
      if (counterpart === null) fail("Only direct conversations with a friend can receive messages here.");
      friendId = counterpart;
    }

    await sharesBetween(ctx, user.id, friendId);
    const thread = await getOrCreateDirectFor(ctx, user.id, friendId);
    if (thread === null) fail(NOT_A_FRIEND);
    const clientId = args.client_id ?? crypto.randomUUID();
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
    return { thread_id: thread.thread_id, message: messageOut(sent, user.id, await namesOf(ctx, [user.id])) };
  },
});

export const markRead = internalMutation({
  args: { user_id: v.string(), friend: v.optional(v.string()), thread_id: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    let threadId = args.thread_id;
    if (args.friend !== undefined) {
      const friendId = await resolveFriendId(ctx, user.id, args.friend);
      const chat = await directThreadState(ctx, user.id, friendId);
      if (chat.thread_id === null) return { thread_id: null, unread_count: 0 };
      threadId = chat.thread_id;
    } else if (threadId === undefined || !(await canAccessThread(ctx, threadId, user.id))) {
      fail(NO_CONVERSATION);
    }
    const [newest] = await liveMessagesBefore(ctx, threadId, null, 1);
    if (newest === undefined) return { thread_id: threadId, unread_count: 0 };
    const state = await markReadFor(ctx, user.id, { thread_id: threadId, through_message_id: newest.id });
    return { thread_id: threadId, unread_count: state.unread_count };
  },
});

const SHARE_REFUSED = {
  no_identifier: "username_or_email is required.",
  not_found: "No Tidex user has that username or verified email address. Check the spelling with the user.",
  self: "That is the user's own account.",
  blocked: "The user can't share shifts with this person.",
};

export const startShare = internalMutation({
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
        await directThreadState(ctx, user.id, friendId),
      ),
    };
  },
});

export const updateSharing = internalMutation({
  args: {
    user_id: v.string(),
    friend: v.string(),
    show_my_earnings: v.optional(v.boolean()),
    notify_them: v.optional(v.boolean()),
    hidden: v.optional(v.boolean()),
    notify_me: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const friendId = await resolveFriendId(ctx, user.id, args.friend);
    const { mine, theirs } = await sharesBetween(ctx, user.id, friendId);
    if (args.show_my_earnings !== undefined || args.notify_them !== undefined) {
      if (mine === null) fail("The user doesn't share their shifts with this friend. Start sharing with username_or_email first.");
      await updateMyShareFor(ctx, user.id, {
        viewer_id: friendId,
        ...(args.show_my_earnings === undefined ? {} : { show_earnings: args.show_my_earnings }),
        ...(args.notify_them === undefined ? {} : { owner_muted: !args.notify_them }),
      });
    }
    if (args.hidden !== undefined || args.notify_me !== undefined) {
      if (theirs === null) fail("This friend doesn't share their shifts with the user, so there is nothing to hide or mute.");
      await updateSharerFor(ctx, user.id, {
        owner_id: friendId,
        hidden: args.hidden,
        muted: args.notify_me === undefined ? undefined : !args.notify_me,
      });
    }
    return {
      friend: friendEntry(
        await personOf(ctx, friendId),
        await shareBetween(ctx, friendId, user.id),
        await shareBetween(ctx, user.id, friendId),
        await directThreadState(ctx, user.id, friendId),
      ),
    };
  },
});

export const stopSharing = internalMutation({
  args: { user_id: v.string(), friend: v.string() },
  handler: async (ctx, { user_id, friend }) => {
    const user = await requireUser(ctx, user_id);
    const friendId = await resolveFriendId(ctx, user.id, friend);
    if (await pairBlocked(ctx, user.id, friendId)) fail(NOT_A_FRIEND);
    const share = await shareBetween(ctx, user.id, friendId);
    if (share !== null && !(await removeShareFor(ctx, user.id, friendId))) fail(NOT_A_FRIEND);
    return { id: friendId, i_share_with_them: false };
  },
});

export const socialTools: McpTool[] = [
  tool(specs.listFriends, (ctx, user_id) => ctx.runQuery(internal.mcpSocial.listFriends, { user_id })),
  tool(specs.getFriendSchedule, (ctx, user_id, args) => ctx.runQuery(internal.mcpSocial.friendSchedule, { user_id, ...args })),
  tool(specs.getMessages, (ctx, user_id, args) =>
    args.mode === "inbox"
      ? ctx.runQuery(internal.mcpSocial.listConversations, { user_id, limit: args.limit, cursor: args.cursor })
      : ctx.runQuery(internal.mcpSocial.readConversation, {
          user_id,
          friend: args.friend,
          thread_id: args.thread_id,
          limit: args.limit,
          before_message_id: args.before_message_id,
        }),
  ),
  tool(specs.sendMessage, (ctx, user_id, args) => ctx.runMutation(internal.mcpSocial.sendMessage, { user_id, ...args })),
  tool(specs.markRead, (ctx, user_id, args) => ctx.runMutation(internal.mcpSocial.markRead, { user_id, ...args })),
  tool(specs.updateSharing, async (ctx, user_id, args) =>
    args.mode === "start"
      ? ctx.runMutation(internal.mcpSocial.startShare, {
          user_id,
          target_id: await shareTargetFor(ctx, args.identifier),
          show_earnings: args.show_earnings,
        })
      : ctx.runMutation(internal.mcpSocial.updateSharing, {
          user_id,
          friend: args.friend,
          show_my_earnings: args.show_my_earnings,
          notify_them: args.notify_them,
          hidden: args.hidden,
          notify_me: args.notify_me,
        }),
  ),
  tool(specs.stopSharing, (ctx, user_id, args) => ctx.runMutation(internal.mcpSocial.stopSharing, { user_id, ...args })),
];
