import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { nextRevision } from "./lib/revision";
import { publicRow, reject } from "./lib/syncWrite";

/**
 * One row per user. The app sends the whole row and the last write wins, as with the
 * Postgres upsert on user_id. Missing fields get the Postgres defaults on first write.
 */
export const upsert = mutation({
  args: {
    shared_shifts_enabled: v.optional(v.boolean()),
    shift_reminders_enabled: v.optional(v.boolean()),
    shift_reminder_minutes_array: v.optional(v.array(v.number())),
  },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    if ((args.shift_reminder_minutes_array?.length ?? 0) > 4) reject("invalid_row", "max_four_reminders");
    const existing = await ctx.db
      .query("notification_preferences")
      .withIndex("by_user_revision", (q) => q.eq("user_id", user.id))
      .unique();
    const fields = {
      ...args,
      updated_at: new Date().toISOString(),
      revision: await nextRevision(ctx),
    };
    if (existing !== null) {
      await ctx.db.patch(existing._id, fields);
      return publicRow((await ctx.db.get(existing._id))!);
    }
    const id = await ctx.db.insert("notification_preferences", {
      user_id: user.id,
      shared_shifts_enabled: true,
      shift_reminders_enabled: true,
      shift_reminder_minutes_array: [300],
      ...fields,
    });
    return publicRow((await ctx.db.get(id))!);
  },
});
