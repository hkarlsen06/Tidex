import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { isScheduleTimeZone, saveScheduleTimeZone, scheduleTimeZone } from "./lib/scheduleTimeZone";
import { reject, requireExpectedUser } from "./lib/syncWrite";

export const mine = query({
  args: {},
  handler: async ctx => {
    const { user } = await requireViewer(ctx);
    return await scheduleTimeZone(ctx, user.id);
  },
});

export const setMine = mutation({
  args: { time_zone: v.string(), expected_user_id: v.string() },
  handler: async (ctx, { time_zone, expected_user_id }) => {
    const { user, impersonationSessionId } = await requireViewer(ctx);
    requireExpectedUser(user.id, expected_user_id);
    if (impersonationSessionId !== null) reject("not_authorized");
    if (!isScheduleTimeZone(time_zone)) reject("invalid_time_zone");
    await saveScheduleTimeZone(ctx, user.id, time_zone, false);
    return time_zone;
  },
});

/** Run once before shipping the client. Repeat pages safely; never overwrite an owner's choice. */
export const backfill = internalMutation({
  args: { cursor: v.union(v.string(), v.null()), apply: v.boolean() },
  handler: async (ctx, { cursor, apply }) => {
    const page = await ctx.db.query("user_app_activity").paginate({ cursor, numItems: 100 });
    let eligible = 0;
    for (const row of page.page) {
      if (!isScheduleTimeZone(row.time_zone)) continue;
      if (await scheduleTimeZone(ctx, row.user_id) !== null) continue;
      eligible += 1;
      if (apply) await saveScheduleTimeZone(ctx, row.user_id, row.time_zone, true);
    }
    return { scanned: page.page.length, eligible, applied: apply, isDone: page.isDone, cursor: page.continueCursor };
  },
});
