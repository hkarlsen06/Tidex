import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { type MutationCtx, mutation, type QueryCtx, query } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import {
  canAccessThread,
  membership,
  pairBlocked,
  threadSummary,
} from "./lib/messaging";
import { queueAbuseReport, queueScreenshot, queueTyping } from "./lib/notify";
import { nextRevision } from "./lib/revision";
import { reject } from "./lib/syncWrite";
import { literals } from "./lib/validators";

export async function threadById(ctx: QueryCtx, id: string) {
  return await ctx.db
    .query("threads")
    .withIndex("by_uuid", (q) => q.eq("id", id))
    .unique();
}

export async function requireAccess(ctx: QueryCtx, threadId: string, userId: string) {
  if (!(await canAccessThread(ctx, threadId, userId))) reject("thread_access_denied", "Thread access denied");
}

/**
 * The viewer's threads, newest first, with the unread direct message count. Replaces
 * get_inbox_sync_snapshot_v2, list_inbox_events_v2, list_my_threads and
 * get_unread_direct_message_count. Subscribe to it to keep the list current.
 */
export const inbox = query({
  args: {
    limit: v.optional(v.number()),
    before_last_message_at: v.optional(v.string()),
    before_thread_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    const memberships = await ctx.db
      .query("thread_memberships")
      .withIndex("by_user_revision", (q) => q.eq("user_id", user.id))
      .collect();
    const summaries = (
      await Promise.all(
        memberships
          .filter((m) => m.status === "active")
          .map(async (m) => {
            const thread = await threadById(ctx, m.thread_id);
            return thread === null ? null : await threadSummary(ctx, thread, user.id);
          }),
      )
    )
      .filter((s) => s !== null)
      .sort(
        (a, b) =>
          b.last_message_at.localeCompare(a.last_message_at) || b.thread_id.localeCompare(a.thread_id),
      );

    const unread = summaries
      .filter((s) => s.kind === "direct")
      .reduce((sum, s) => sum + s.unread_count, 0);
    const { before_last_message_at: at, before_thread_id: id } = args;
    const after =
      at === undefined || id === undefined
        ? summaries
        : summaries.filter((s) => s.last_message_at < at || (s.last_message_at === at && s.thread_id < id));
    const limit = Math.min(Math.max(Math.floor(args.limit ?? 30), 1), 100);
    const page = after.slice(0, limit);
    const last = page.at(-1);
    return {
      threads: page,
      unread_direct_message_count: unread,
      has_more: after.length > limit,
      next_cursor:
        after.length > limit && last !== undefined
          ? { before_last_message_at: last.last_message_at, before_thread_id: last.thread_id }
          : null,
    };
  },
});

/** Read state for every member, for read receipts. Replaces the thread_user_state select. */
export const states = query({
  args: { thread_id: v.string() },
  handler: async (ctx, { thread_id }) => {
    const { user } = await requireViewer(ctx);
    if (!(await canAccessThread(ctx, thread_id, user.id))) return [];
    const memberships = await ctx.db
      .query("thread_memberships")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", thread_id))
      .collect();
    const rows = await Promise.all(
      memberships.map((m) =>
        ctx.db
          .query("thread_user_state")
          .withIndex("by_thread_user", (q) => q.eq("thread_id", thread_id).eq("user_id", m.user_id))
          .unique(),
      ),
    );
    return rows.filter((r) => r !== null).map(stateRow);
  },
});

function stateRow(s: Doc<"thread_user_state">) {
  return {
    thread_id: s.thread_id,
    user_id: s.user_id,
    last_read_message_id: s.last_read_message_id ?? null,
    last_read_at: s.last_read_at ?? null,
    muted: s.muted,
    unread_count: s.unread_count,
    updated_at: s.updated_at,
  };
}

export async function ensureState(ctx: MutationCtx, threadId: string, userId: string) {
  const existing = await ctx.db
    .query("thread_user_state")
    .withIndex("by_thread_user", (q) => q.eq("thread_id", threadId).eq("user_id", userId))
    .unique();
  if (existing !== null) return existing;
  const id = await ctx.db.insert("thread_user_state", {
    thread_id: threadId,
    user_id: userId,
    muted: false,
    unread_count: 0,
    updated_at: new Date().toISOString(),
    revision: await nextRevision(ctx),
  });
  return (await ctx.db.get(id))!;
}

/** Port of get_or_create_direct_thread. Needs an unblocked share in either direction. */
export const getOrCreateDirect = mutation({
  args: { other_user_id: v.string() },
  handler: async (ctx, { other_user_id }) => {
    const { user } = await requireViewer(ctx);
    const allowed =
      other_user_id !== user.id &&
      !(await pairBlocked(ctx, user.id, other_user_id)) &&
      (await Promise.all(
        [
          [user.id, other_user_id],
          [other_user_id, user.id],
        ].map(([owner, viewer]) =>
          ctx.db
            .query("shift_shares")
            .withIndex("by_owner_viewer", (q) => q.eq("owner_id", owner).eq("viewer_id", viewer))
            .unique(),
        ),
      )).some((s) => s !== null);
    if (!allowed) reject("direct_thread_not_allowed", "Direct thread creation is not allowed for this user pair");

    const [low, high] = user.id < other_user_id ? [user.id, other_user_id] : [other_user_id, user.id];
    const now = new Date().toISOString();
    let threadId = (
      await ctx.db
        .query("direct_threads")
        .withIndex("by_pair", (q) => q.eq("user_low_id", low).eq("user_high_id", high))
        .unique()
    )?.thread_id;
    if (threadId === undefined) {
      threadId = crypto.randomUUID();
      await ctx.db.insert("threads", {
        id: threadId,
        kind: "direct",
        created_by_user_id: user.id,
        metadata: {},
        last_message_at: now,
        created_at: now,
        revision: await nextRevision(ctx),
      });
      await ctx.db.insert("direct_threads", {
        thread_id: threadId,
        user_low_id: low,
        user_high_id: high,
        created_at: now,
      });
    }
    for (const memberId of [low, high]) {
      const existing = await membership(ctx, threadId, memberId);
      if (existing === null) {
        await ctx.db.insert("thread_memberships", {
          thread_id: threadId,
          user_id: memberId,
          role: "member",
          status: "active",
          joined_at: now,
          revision: await nextRevision(ctx),
        });
      } else if (existing.status !== "active" || existing.role !== "member") {
        await ctx.db.patch(existing._id, {
          role: "member",
          status: "active",
          left_at: undefined,
          revision: await nextRevision(ctx),
        });
      }
      await ensureState(ctx, threadId, memberId);
    }
    return await threadSummary(ctx, (await threadById(ctx, threadId))!, user.id);
  },
});

/** Port of mark_thread_read. Only moves the read marker forward. */
export const markRead = mutation({
  args: { thread_id: v.string(), through_message_id: v.string() },
  handler: async (ctx, { thread_id, through_message_id }) => {
    const { user } = await requireViewer(ctx);
    await requireAccess(ctx, thread_id, user.id);
    const target = await ctx.db
      .query("messages")
      .withIndex("by_uuid", (q) => q.eq("id", through_message_id))
      .unique();
    if (target === null || target.thread_id !== thread_id) {
      reject("invalid", "Read marker message does not belong to the thread");
    }
    const state = await ensureState(ctx, thread_id, user.id);
    const current =
      state.last_read_message_id === undefined
        ? null
        : await ctx.db
            .query("messages")
            .withIndex("by_uuid", (q) => q.eq("id", state.last_read_message_id!))
            .unique();
    const after = (m: Doc<"messages">, than: Doc<"messages">) =>
      m.created_at > than.created_at || (m.created_at === than.created_at && m.id > than.id);
    if (current === null || after(target, current)) {
      const newlyRead = (
        await ctx.db
          .query("messages")
          .withIndex("by_thread_created_at", (q) => {
            const thread = q.eq("thread_id", thread_id);
            return current === null
              ? thread.lte("created_at", target.created_at)
              : thread.gte("created_at", current.created_at).lte("created_at", target.created_at);
          })
          .collect()
      ).filter(
        (m) =>
          m.sender_user_id !== user.id &&
          m.deleted_at === undefined &&
          !after(m, target) &&
          (current === null || after(m, current)),
      ).length;
      await ctx.db.patch(state._id, {
        last_read_message_id: target.id,
        last_read_at: target.created_at,
        unread_count: Math.max(state.unread_count - newlyRead, 0),
        updated_at: new Date().toISOString(),
        revision: await nextRevision(ctx),
      });
    }
    return stateRow((await ctx.db.get(state._id))!);
  },
});

export const setMuted = mutation({
  args: { thread_id: v.string(), muted: v.boolean() },
  handler: async (ctx, { thread_id, muted }) => {
    const { user } = await requireViewer(ctx);
    await requireAccess(ctx, thread_id, user.id);
    const state = await ensureState(ctx, thread_id, user.id);
    await ctx.db.patch(state._id, {
      muted,
      updated_at: new Date().toISOString(),
      revision: await nextRevision(ctx),
    });
    return stateRow((await ctx.db.get(state._id))!);
  },
});

/** Typing start and stop. Replaces the typing_start and typing_stop broadcasts. */
export const setTyping = mutation({
  args: { thread_id: v.string(), typing: v.boolean() },
  handler: async (ctx, { thread_id, typing }) => {
    const { user, impersonationSessionId } = await requireViewer(ctx);
    if (impersonationSessionId !== null) return null;
    await requireAccess(ctx, thread_id, user.id);
    const existing = await ctx.db
      .query("typing_indicators")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", thread_id).eq("user_id", user.id))
      .unique();
    if (!typing) {
      if (existing !== null) await ctx.db.delete(existing._id);
      return null;
    }
    const updated_at = new Date().toISOString();
    if (existing === null) await ctx.db.insert("typing_indicators", { thread_id, user_id: user.id, updated_at });
    else await ctx.db.patch(existing._id, { updated_at });
    return null;
  },
});

/**
 * Other members typing in the viewer's threads, or in one thread when `thread_id` is
 * given. The app drops rows whose updated_at is more than a few seconds old, because a
 * subscription does not rerun when time passes.
 */
export const typing = query({
  args: { thread_id: v.optional(v.string()) },
  handler: async (ctx, { thread_id }) => {
    const { user } = await requireViewer(ctx);
    const threadIds =
      thread_id !== undefined
        ? [thread_id]
        : (
            await ctx.db
              .query("thread_memberships")
              .withIndex("by_user_revision", (q) => q.eq("user_id", user.id))
              .collect()
          )
            .filter((m) => m.status === "active")
            .map((m) => m.thread_id);
    const rows = [];
    for (const id of threadIds) {
      if (!(await canAccessThread(ctx, id, user.id))) continue;
      const typing = await ctx.db
        .query("typing_indicators")
        .withIndex("by_thread_user", (q) => q.eq("thread_id", id))
        .collect();
      rows.push(
        ...typing
          .filter((t) => t.user_id !== user.id)
          .map((t) => ({ thread_id: t.thread_id, user_id: t.user_id, sent_at_ms: Date.parse(t.updated_at) })),
      );
    }
    return rows;
  },
});

/** Port of create_abuse_report. */
export const reportAbuse = mutation({
  args: {
    thread_id: v.string(),
    reported_user_id: v.string(),
    message_id: v.optional(v.string()),
    reason: literals(
      "harassment_or_bullying",
      "sexual_content",
      "hate_or_discriminatory_content",
      "violence_or_threats",
      "spam",
      "inappropriate_profile_or_conduct",
      "other",
    ),
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    if (args.reported_user_id === user.id) reject("invalid", "Cannot report yourself");
    const note = args.note?.trim() || undefined;
    if (note !== undefined && [...note].length > 500) reject("invalid", "Report note must be 500 characters or less");
    const active = async (userId: string) => {
      const m = await membership(ctx, args.thread_id, userId);
      return m !== null && m.status === "active" && m.left_at === undefined;
    };
    if (!(await active(user.id))) reject("thread_access_denied", "Thread not accessible");
    if (!(await active(args.reported_user_id))) reject("invalid", "Reported user is not a member of this thread");
    if (args.message_id !== undefined) {
      const message = await ctx.db
        .query("messages")
        .withIndex("by_uuid", (q) => q.eq("id", args.message_id!))
        .unique();
      if (
        message === null ||
        message.thread_id !== args.thread_id ||
        message.sender_user_id !== args.reported_user_id
      ) {
        reject("invalid", "Reported message is invalid for this thread and user");
      }
    }
    const reportId = await ctx.db.insert("abuse_reports", {
      id: crypto.randomUUID(),
      reporter_user_id: user.id,
      reported_user_id: args.reported_user_id,
      thread_id: args.thread_id,
      message_id: args.message_id,
      reason: args.reason,
      note,
      status: "open",
      created_at: new Date().toISOString(),
    });
    await queueAbuseReport(ctx, (await ctx.db.get(reportId))!);
    return null;
  },
});

/** Port of queue_thread_typing_notification. True when a push was queued. */
export const queueTypingNotification = mutation({
  args: { thread_id: v.string() },
  handler: async (ctx, { thread_id }) => {
    const { user, impersonationSessionId } = await requireViewer(ctx);
    if (impersonationSessionId !== null) return false;
    await requireAccess(ctx, thread_id, user.id);
    return await queueTyping(ctx, thread_id, user.id);
  },
});

/** Port of report_thread_screenshot: tells the other member of a direct thread. */
export const reportScreenshot = mutation({
  args: { thread_id: v.string() },
  handler: async (ctx, { thread_id }) => {
    const { user } = await requireViewer(ctx);
    const member = await membership(ctx, thread_id, user.id);
    if (member === null || member.status !== "active") reject("thread_access_denied", "No access to thread");
    const thread = await threadById(ctx, thread_id);
    if (thread?.kind !== "direct") return { success: true, skipped: true };
    const recipient = (
      await ctx.db
        .query("thread_memberships")
        .withIndex("by_thread_user", (q) => q.eq("thread_id", thread_id))
        .collect()
    ).find((m) => m.status === "active" && m.user_id !== user.id);
    if (recipient === undefined) return { success: true, skipped: true };
    await queueScreenshot(ctx, user.id, recipient.user_id, thread_id);
    return { success: true };
  },
});

