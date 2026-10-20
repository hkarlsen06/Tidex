import { v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";
import { hashCalendarToken } from "./calendarSubscriptions";
import { userByUuid } from "./lib/auth";
import type { CalendarData } from "./lib/calendarFeed/types";
import { literals } from "./lib/validators";

// The database half of the calendar-feed Edge Function. http.ts serves the feed at
// GET /calendar-feed/<token>.ics. On cutover night Caddy sends the old
// api.tidex.no/functions/v1/calendar-feed/... URLs, which people have saved in their
// calendar apps, to that route.

const TOKEN = /^tidex_cal_[0-9a-f]{64}$/;
const TOUCH_EVERY_MS = 15 * 60_000;

/** internal.resolve_calendar_subscription_token. Touches last_used_at at most every 15 minutes. */
export const resolve = internalMutation({
  args: { raw_token: v.string() },
  handler: async (ctx, { raw_token }) => {
    if (!TOKEN.test(raw_token)) return null;
    const hash = await hashCalendarToken(raw_token);
    const token = (
      await ctx.db
        .query("calendar_subscription_tokens")
        .withIndex("by_token_hash", (q) => q.eq("token_hash", hash))
        .collect()
    ).find((t) => t.revoked_at === undefined);
    if (token === undefined) return null;
    if (token.last_used_at === undefined || Date.parse(token.last_used_at) < Date.now() - TOUCH_EVERY_MS) {
      await ctx.db.patch(token._id, { last_used_at: new Date().toISOString() });
    }
    return {
      user_id: token.user_id,
      content_mode: token.content_mode,
      locale: (await userByUuid(ctx, token.user_id))?.locale ?? null,
    };
  },
});

/** loadCalendarData: the user's live shifts, recurring shifts, jobs and events in the window. */
export const data = internalQuery({
  args: {
    user_id: v.string(),
    content_mode: literals("events_only", "shifts_only", "shifts_and_events"),
    start_date: v.string(),
    end_date: v.string(),
  },
  handler: async (ctx, { user_id, content_mode, start_date, end_date }): Promise<CalendarData> => {
    const shifts = content_mode !== "events_only";
    const events = content_mode !== "shifts_only";
    const live = <T extends { deleted_at?: string }>(rows: T[]) => rows.filter((r) => r.deleted_at === undefined);
    return {
      shifts: shifts
        ? live(
            await ctx.db
              .query("user_shifts")
              .withIndex("by_user_shift_date", (q) => q.eq("user_id", user_id).gte("shift_date", start_date).lte("shift_date", end_date))
              .collect(),
          ).map((s) => ({
            id: s.id,
            shift_date: s.shift_date,
            start_time: s.start_time,
            end_time: s.end_time,
            note: s.note ?? null,
            job_id: s.job_id,
            updated_at: s.updated_at,
          }))
        : [],
      recurringShifts: shifts
        ? live(
            await ctx.db
              .query("recurring_shifts")
              .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
              .collect(),
          ).map((r) => ({
            id: r.id,
            start_time: r.start_time,
            end_time: r.end_time,
            repeat_interval_weeks: r.repeat_interval_weeks,
            selected_days: r.selected_days,
            end_condition: r.end_condition ?? null,
            exclusions: r.exclusions ?? null,
            date_specific_notes: r.date_specific_notes ?? null,
            job_id: r.job_id,
            updated_at: r.updated_at,
          }))
        : [],
      jobs: shifts
        ? live(
            await ctx.db
              .query("jobs")
              .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
              .collect(),
          ).map((j) => ({ id: j.id, name: j.name }))
        : [],
      events: events
        ? live(
            await ctx.db
              .query("events")
              .withIndex("by_user_start_date", (q) => q.eq("user_id", user_id).lte("start_date", end_date))
              .collect(),
          )
            .filter((e) => e.end_date >= start_date)
            .sort(
              (a, b) =>
                a.start_date.localeCompare(b.start_date) ||
                a.end_date.localeCompare(b.end_date) ||
                (a.start_time ?? "").localeCompare(b.start_time ?? ""),
            )
            .map((e) => ({
              id: e.id,
              start_date: e.start_date,
              end_date: e.end_date,
              is_all_day: e.is_all_day,
              start_time: e.start_time ?? null,
              end_time: e.end_time ?? null,
              note: e.note,
              updated_at: e.updated_at,
            }))
        : [],
    } as CalendarData;
  },
});
