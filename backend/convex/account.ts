import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { action, internalMutation, internalQuery, type MutationCtx } from "./_generated/server";
import { getViewer, userByUuid } from "./lib/auth";
import { deleteClerkUser } from "./lib/clerk";

// Port of the delete-account Edge Function and prepare_user_for_deletion. Postgres
// deleted the auth.users row and its foreign keys cascaded. Convex has no foreign keys,
// so `step` deletes from every table that holds the user's uuid, a batch per call, and
// the action repeats it until nothing is left. Then it deletes the Clerk users.

const BATCH = 400;

type Step = (ctx: MutationCtx, user: Doc<"users">, budget: number) => Promise<number>;

/** Deletes up to `budget` documents, plus their stored files. Returns how many it touched. */
async function remove(ctx: MutationCtx, docs: { _id: Id<any> }[], budget: number, files: (d: any) => Id<"_storage">[] = () => []) {
  const batch = docs.slice(0, budget);
  for (const d of batch) {
    for (const file of files(d)) await ctx.storage.delete(file);
    await ctx.db.delete(d._id);
  }
  return batch.length;
}

const byUserRevision = (table: any): Step => async (ctx, user, budget) =>
  remove(
    ctx,
    await (ctx.db.query(table) as any).withIndex("by_user_revision", (q: any) => q.eq("user_id", user.id)).take(budget),
    budget,
  );

const byUser = (table: any): Step => async (ctx, user, budget) =>
  remove(ctx, await (ctx.db.query(table) as any).withIndex("by_user", (q: any) => q.eq("user_id", user.id)).take(budget), budget);

/** A thread and everything in it: memberships, state, messages, images, reactions, typing. */
async function removeThread(ctx: MutationCtx, threadId: string, budget: number): Promise<number> {
  let used = 0;
  const messages = await ctx.db
    .query("messages")
    .withIndex("by_thread_revision", (q) => q.eq("thread_id", threadId))
    .take(budget);
  for (const m of messages) {
    for (const a of await ctx.db
      .query("message_attachments")
      .withIndex("by_message", (q) => q.eq("message_id", m.id))
      .collect()) {
      await ctx.storage.delete(a.storage_id);
      await ctx.db.delete(a._id);
      used += 1;
    }
    for (const r of await ctx.db
      .query("message_reactions")
      .withIndex("by_message_user_emoji", (q) => q.eq("message_id", m.id))
      .collect()) {
      await ctx.db.delete(r._id);
      used += 1;
    }
    await ctx.db.delete(m._id);
    used += 1;
    if (used >= budget) return used;
  }
  for (const table of ["thread_memberships", "thread_user_state", "typing_indicators"] as const) {
    for (const row of await (ctx.db.query(table) as any).withIndex("by_thread_user", (q: any) => q.eq("thread_id", threadId)).collect()) {
      await ctx.db.delete(row._id);
      used += 1;
    }
  }
  for (const d of await ctx.db
    .query("direct_threads")
    .withIndex("by_thread", (q) => q.eq("thread_id", threadId))
    .collect()) {
    await ctx.db.delete(d._id);
  }
  const thread = await ctx.db
    .query("threads")
    .withIndex("by_uuid", (q) => q.eq("id", threadId))
    .unique();
  if (thread !== null) {
    if (thread.avatar_storage_id !== undefined) await ctx.storage.delete(thread.avatar_storage_id);
    await ctx.db.delete(thread._id);
  }
  return used + 1;
}

const steps: Step[] = [
  // Reports can't outlive either side, and reviews lose their reviewer.
  async (ctx, user, budget) => {
    let used = 0;
    for (const r of await ctx.db.query("abuse_reports").collect()) {
      if (used >= budget) break;
      if (r.reporter_user_id === user.id || r.reported_user_id === user.id) {
        await ctx.db.delete(r._id);
        used += 1;
      } else if (r.reviewed_by === user.id) {
        await ctx.db.patch(r._id, { reviewed_by: undefined });
        used += 1;
      }
    }
    return used;
  },
  // Direct threads go entirely, for both people.
  async (ctx, user, budget) => {
    let used = 0;
    while (used < budget) {
      const direct =
        (await ctx.db
          .query("direct_threads")
          .withIndex("by_pair", (q) => q.eq("user_low_id", user.id))
          .first()) ??
        (await ctx.db
          .query("direct_threads")
          .withIndex("by_user_high", (q) => q.eq("user_high_id", user.id))
          .first());
      if (direct === null) return used;
      used += await removeThread(ctx, direct.thread_id, budget - used);
    }
    return used;
  },
  // Other threads keep going without the user and their messages.
  byUserRevision("thread_user_state"),
  byUserRevision("thread_memberships"),
  async (ctx, user, budget) => {
    const messages = await ctx.db
      .query("messages")
      .withIndex("by_sender", (q) => q.eq("sender_user_id", user.id))
      .take(budget);
    let used = 0;
    for (const m of messages) {
      for (const a of await ctx.db
        .query("message_attachments")
        .withIndex("by_message", (q) => q.eq("message_id", m.id))
        .collect()) {
        await ctx.storage.delete(a.storage_id);
        await ctx.db.delete(a._id);
      }
      await ctx.db.delete(m._id);
      used += 1;
    }
    return used;
  },
  byUser("message_reactions"),
  // Devices and their Live Activities.
  async (ctx, user, budget) => {
    const devices = await ctx.db
      .query("push_devices")
      .withIndex("by_user", (q) => q.eq("user_id", user.id))
      .take(budget);
    for (const d of devices) {
      for (const l of await ctx.db
        .query("live_activity_deliveries")
        .withIndex("by_push_device_shift", (q) => q.eq("push_device_id", d.id))
        .collect()) {
        await ctx.db.delete(l._id);
      }
      await ctx.db.delete(d._id);
    }
    return devices.length;
  },
  byUser("app_account_tokens"),
  async (ctx, user, budget) =>
    remove(
      ctx,
      await ctx.db
        .query("notifications_outbox")
        .withIndex("by_recipient_type_thread", (q) => q.eq("recipient_id", user.id))
        .take(budget),
      budget,
    ),
  async (ctx, user, budget) =>
    remove(
      ctx,
      await ctx.db
        .query("notifications_outbox")
        .withIndex("by_owner_type_status", (q) => q.eq("owner_id", user.id))
        .take(budget),
      budget,
    ),
  // What the auth.users foreign keys cascaded to.
  byUserRevision("user_shifts"),
  byUserRevision("recurring_shifts"),
  byUserRevision("wage_snapshots"),
  byUserRevision("payroll_adjustments"),
  byUserRevision("events"),
  byUserRevision("jobs"),
  async (ctx, user, budget) =>
    remove(
      ctx,
      await ctx.db
        .query("user_settings")
        .withIndex("by_user_revision", (q) => q.eq("user_id", user.id))
        .take(budget),
      budget,
      (s: Doc<"user_settings">) => (s.profile_picture_storage_id === undefined ? [] : [s.profile_picture_storage_id]),
    ),
  byUserRevision("notification_preferences"),
  async (ctx, user, budget) =>
    remove(
      ctx,
      await ctx.db
        .query("shift_shares")
        .withIndex("by_owner_revision", (q) => q.eq("owner_id", user.id))
        .take(budget),
      budget,
    ),
  async (ctx, user, budget) =>
    remove(
      ctx,
      await ctx.db
        .query("shift_shares")
        .withIndex("by_viewer_revision", (q) => q.eq("viewer_id", user.id))
        .take(budget),
      budget,
    ),
  byUser("feedback"),
  byUser("subscriptions"),
  byUser("calendar_subscription_tokens"),
  async (ctx, user, budget) =>
    remove(
      ctx,
      await ctx.db
        .query("onboarding_funnel_steps")
        .withIndex("by_user_step", (q) => q.eq("user_id", user.id))
        .take(budget),
      budget,
    ),
  byUser("user_app_activity"),
  byUser("app_activity_hours"),
  byUser("legacy_identities"),
  byUser("clerk_user_aliases"),
  async (ctx, user, budget) => {
    let used = 0;
    for (const u of await ctx.db.query("attachment_uploads").collect()) {
      if (used >= budget || u.user_id !== user.id) continue;
      await ctx.storage.delete(u.storage_id);
      await ctx.db.delete(u._id);
      used += 1;
    }
    return used;
  },
  // Diagnostics stay for debugging, without the user id.
  async (ctx, user, budget) => {
    const rows = await ctx.db
      .query("auth_diagnostic_events")
      .withIndex("by_user_occurred_at", (q) => q.eq("user_id", user.id))
      .take(budget);
    for (const r of rows) await ctx.db.patch(r._id, { user_id: undefined });
    return rows.length;
  },
  async (ctx, user, budget) =>
    remove(
      ctx,
      await ctx.db
        .query("profiles")
        .withIndex("by_uuid", (q) => q.eq("id", user.id))
        .take(budget),
      budget,
    ),
];

/** Who may delete: the user themselves, not an admin impersonating them. */
export const deletionTarget = internalQuery({
  args: {},
  handler: async (ctx) => {
    const viewer = await getViewer(ctx);
    if (viewer === null) return { error: "Not authenticated" };
    if (viewer.impersonationSessionId !== null) return { error: "Account deletion is not allowed during impersonation" };
    const beingImpersonated = (await ctx.db.query("impersonation_sessions").collect()).some(
      (s) => s.target_user_id === viewer.user.id && s.ended_at === undefined && Date.parse(s.expires_at) > Date.now(),
    );
    if (beingImpersonated) return { error: "Account deletion is not allowed during impersonation" };
    const aliases = await ctx.db
      .query("clerk_user_aliases")
      .withIndex("by_user", (q) => q.eq("user_id", viewer.user.id))
      .collect();
    return {
      user_id: viewer.user.id,
      clerk_user_ids: [
        ...(viewer.user.clerk_user_id === undefined ? [] : [viewer.user.clerk_user_id]),
        ...aliases.map((a) => a.clerk_user_id),
      ],
    };
  },
});

/** One batch of deletion. Returns true when only the users row was left and is gone. */
export const step = internalMutation({
  args: { user_id: v.string(), first: v.boolean() },
  handler: async (ctx, { user_id, first }) => {
    const user = await userByUuid(ctx, user_id);
    if (user === null) return true;
    if (first) {
      await ctx.db.insert("admin_audit_log", {
        id: crypto.randomUUID(),
        admin_id: user.id,
        admin_email: user.email ?? "unknown",
        action: "user_deleted_self",
        target_user_id: user.id,
        target_email: user.email ?? "unknown",
        metadata: { deletion_type: "self_service", deleted_at: new Date().toISOString() },
        created_at: new Date().toISOString(),
      });
    }
    let budget = BATCH;
    for (const run of steps) {
      budget -= await run(ctx, user, budget);
      if (budget <= 0) return false;
    }
    await ctx.db.delete(user._id);
    return true;
  },
});

export const deleteAccount = action({
  args: {},
  handler: async (ctx): Promise<{ success: boolean; error?: string }> => {
    const target = await ctx.runQuery(internal.account.deletionTarget, {});
    if ("error" in target) throw new ConvexError({ code: "forbidden", message: target.error });
    let first = true;
    while (!(await ctx.runMutation(internal.account.step, { user_id: target.user_id, first }))) first = false;
    for (const id of target.clerk_user_ids) await deleteClerkUser(id);
    return { success: true };
  },
});
