import type { MutationCtx, QueryCtx } from "../_generated/server";
import { nextRevision } from "./revision";

/** Named zones shared by Intl and Foundation, without abbreviations or numeric offsets. */
export function isScheduleTimeZone(value: string | undefined): value is string {
  if (value === undefined || value.length > 100) return false;
  if (value !== "UTC" && !/^[A-Z][A-Za-z_+-]*(?:\/[A-Z][A-Za-z0-9_+-]*)+$/.test(value)) return false;
  try {
    new Intl.DateTimeFormat("en", { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

export async function scheduleTimeZone(ctx: QueryCtx, userId: string) {
  const profile = await ctx.db.query("profiles").withIndex("by_uuid", q => q.eq("id", userId)).unique();
  return isScheduleTimeZone(profile?.schedule_time_zone) ? profile.schedule_time_zone : null;
}

export async function saveScheduleTimeZone(
  ctx: MutationCtx,
  userId: string,
  zone: string,
  onlyIfAbsent: boolean,
) {
  const profile = await ctx.db.query("profiles").withIndex("by_uuid", q => q.eq("id", userId)).unique();
  if (onlyIfAbsent && profile?.schedule_time_zone !== undefined) return false;
  const now = new Date().toISOString();
  const fields = { schedule_time_zone: zone, updated_at: now, revision: await nextRevision(ctx) };
  if (profile === null) {
    await ctx.db.insert("profiles", { id: userId, created_at: now, ...fields });
  } else {
    await ctx.db.patch(profile._id, fields);
  }
  return true;
}
