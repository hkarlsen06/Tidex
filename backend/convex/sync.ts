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
export const pull = query({
  args: {
    table: literals(
      "jobs",
      "user_shifts",
      "events",
      "recurring_shifts",
      "wage_snapshots",
      "payroll_adjustments",
      "user_settings",
      "notification_preferences",
    ),
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
