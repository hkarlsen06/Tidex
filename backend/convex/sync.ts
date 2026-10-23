import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { query } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { publicRow } from "./lib/syncWrite";
import { literals } from "./lib/validators";
import { settingsRow } from "./userSettings";

const DEFAULT_PAGE = 500;
const MAX_PAGE = 1000;

/**
 * One page of a synced table, oldest revision first. The app passes the last revision
 * it has as `after` and keeps pulling until `done`. Soft-deleted rows are included so
 * the app can remove them locally.
 */
const TABLES = [
  "jobs",
  "user_shifts",
  "events",
  "recurring_shifts",
  "wage_snapshots",
  "payroll_adjustments",
  "user_settings",
  "notification_preferences",
] as const;

export const pull = query({
  args: {
    table: literals(...TABLES),
    after: v.number(),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, { table, after, limit }) => {
    const { user } = await requireViewer(ctx);
    const size = Math.min(Math.max(Math.floor(limit ?? DEFAULT_PAGE), 1), MAX_PAGE);
    const rows = await ctx.db
      .query(table)
      .withIndex("by_user_revision", (q) => q.eq("user_id", user.id).gt("revision", after))
      .take(size);

    const page = await Promise.all(
      rows.map((row) =>
        table === "user_settings" ? settingsRow(ctx, row as Doc<"user_settings">) : publicRow(row),
      ),
    );
    return {
      rows: page,
      cursor: rows.at(-1)?.revision ?? after,
      done: rows.length < size,
    };
  },
});

/**
 * The newest revision in each synced table for the viewer. The app subscribes to this and
 * pulls a table when its number passes the app's cursor, so changes made elsewhere arrive
 * while the app is open. It reads one row per table, so it re-runs only when that changes.
 */
export const revisions = query({
  args: {},
  handler: async (ctx) => {
    const { user } = await requireViewer(ctx);
    const newest = await Promise.all(
      TABLES.map((table) =>
        ctx.db
          .query(table)
          .withIndex("by_user_revision", (q) => q.eq("user_id", user.id))
          .order("desc")
          .first(),
      ),
    );
    return Object.fromEntries(TABLES.map((table, i) => [table, newest[i]?.revision ?? 0]));
  },
});
