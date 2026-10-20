import { v } from "convex/values";
import { query } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { literals } from "./lib/validators";

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
      rows.map(async ({ _id, _creationTime, ...row }) => {
        // The app reads profile_picture_url, as it did from Postgres.
        if ("profile_picture_storage_id" in row && row.profile_picture_storage_id) {
          const { profile_picture_storage_id, ...rest } = row;
          return { ...rest, profile_picture_url: await ctx.storage.getUrl(profile_picture_storage_id) };
        }
        return row;
      }),
    );
    return {
      rows: page,
      cursor: rows.at(-1)?.revision ?? after,
      done: rows.length < size,
    };
  },
});
