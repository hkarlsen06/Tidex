import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { internalMutation, type MutationCtx } from "./_generated/server";

// Ports of the pg_cron purge jobs, plus the two Convex adds. crons.ts runs them at
// the same UTC times. Each run deletes a batch and schedules itself again while there
// is more, so one run never goes past a mutation's write limit.
//
// ponytail: the soft-delete purge scans each synced table, because nothing indexes
// deleted_at. user_shifts, the largest, had 3,283 rows in October 2026. Add a
// deleted_at index when a scan gets slow.

const BATCH = 500;
const DAY_MS = 86_400_000;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

async function deleteAll(ctx: MutationCtx, ids: Id<any>[]) {
  for (const id of ids) await ctx.db.delete(id);
  return ids.length;
}

/** internal.purge_soft_deletes: rows soft-deleted more than 30 days ago go for good. */
export const purgeSoftDeletes = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = ago(30 * DAY_MS);
    let used = 0;
    for (const table of ["events", "payroll_adjustments", "user_shifts", "recurring_shifts", "wage_snapshots", "jobs"] as const) {
      const expired = [];
      for await (const row of ctx.db.query(table)) {
        if (row.deleted_at !== undefined && row.deleted_at < cutoff) expired.push(row._id);
        if (used + expired.length >= BATCH) break;
      }
      used += await deleteAll(ctx, expired);
      if (used >= BATCH) break;
    }
    if (used < BATCH) {
      for await (const m of ctx.db.query("messages")) {
        if (m.deleted_at === undefined || m.deleted_at >= cutoff) continue;
        for (const a of await ctx.db
          .query("message_attachments")
          .withIndex("by_message", (q) => q.eq("message_id", m.id))
          .collect()) {
          await ctx.storage.delete(a.storage_id);
          await ctx.db.delete(a._id);
        }
        for (const r of await ctx.db
          .query("message_reactions")
          .withIndex("by_message_user_emoji", (q) => q.eq("message_id", m.id))
          .collect()) {
          await ctx.db.delete(r._id);
        }
        await ctx.db.delete(m._id);
        if (++used >= BATCH) break;
      }
    }
    if (used >= BATCH) await ctx.scheduler.runAfter(0, internal.maintenance.purgeSoftDeletes, {});
  },
});

/** cleanup-shift-notification-events: sent pushes after 30 days, the rest 6 weeks past due. */
export const cleanupOutbox = internalMutation({
  args: {},
  handler: async (ctx) => {
    const sentCutoff = ago(30 * DAY_MS);
    const dueCutoff = ago(42 * DAY_MS);
    const old = [];
    for await (const n of ctx.db.query("notifications_outbox")) {
      if ((n.status === "sent" && n.created_at < sentCutoff) || (n.status !== "sent" && n.due_at < dueCutoff)) old.push(n._id);
      if (old.length >= BATCH) break;
    }
    if ((await deleteAll(ctx, old)) >= BATCH) await ctx.scheduler.runAfter(0, internal.maintenance.cleanupOutbox, {});
  },
});

/** purge-auth-diagnostic-events: older than 90 days. */
export const purgeDiagnostics = internalMutation({
  args: {},
  handler: async (ctx) => {
    const old = await ctx.db
      .query("auth_diagnostic_events")
      .withIndex("by_occurred_at", (q) => q.lt("occurred_at", ago(90 * DAY_MS)))
      .take(BATCH);
    if ((await deleteAll(ctx, old.map((r) => r._id))) >= BATCH) {
      await ctx.scheduler.runAfter(0, internal.maintenance.purgeDiagnostics, {});
    }
  },
});

/** purge-app-activity-hours: older than 32 days. */
export const purgeActivityHours = internalMutation({
  args: {},
  handler: async (ctx) => {
    const old = await ctx.db
      .query("app_activity_hours")
      .withIndex("by_hour_user", (q) => q.lt("hour", ago(32 * DAY_MS)))
      .take(BATCH);
    if ((await deleteAll(ctx, old.map((r) => r._id))) >= BATCH) {
      await ctx.scheduler.runAfter(0, internal.maintenance.purgeActivityHours, {});
    }
  },
});

/** New in Convex: typing rows the app stopped refreshing, and images uploaded but never sent. */
export const purgeStaleMessagingRows = internalMutation({
  args: {},
  handler: async (ctx) => {
    const typing = await ctx.db
      .query("typing_indicators")
      .withIndex("by_updated_at", (q) => q.lt("updated_at", ago(60 * 60_000)))
      .take(BATCH);
    await deleteAll(ctx, typing.map((t) => t._id));
    const uploads = await ctx.db
      .query("attachment_uploads")
      .withIndex("by_created_at", (q) => q.lt("created_at", ago(DAY_MS)))
      .take(BATCH);
    for (const u of uploads) {
      await ctx.storage.delete(u.storage_id);
      await ctx.db.delete(u._id);
    }
    if (typing.length >= BATCH || uploads.length >= BATCH) {
      await ctx.scheduler.runAfter(0, internal.maintenance.purgeStaleMessagingRows, {});
    }
  },
});
