import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { requireViewer } from "./lib/auth";

const osloDate = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Oslo" });

const cut = (value: string | undefined, max: number) => value?.slice(0, max);

/**
 * Port of record_app_activity. The app calls it each time it comes to the foreground, and
 * right after a sign-in with `signed_in`, which GoTrue's last_sign_in_at used to cover.
 */
export const record = mutation({
  args: {
    app_version: v.optional(v.string()),
    build_number: v.optional(v.string()),
    os_version: v.optional(v.string()),
    device_model: v.optional(v.string()),
    locale: v.optional(v.string()),
    time_zone: v.optional(v.string()),
    app_language: v.optional(v.string()),
    notification_permission: v.optional(v.string()),
    background_refresh: v.optional(v.string()),
    widget_kinds: v.optional(v.array(v.string())),
    appearance: v.optional(v.string()),
    text_size: v.optional(v.string()),
    reduce_motion: v.optional(v.boolean()),
    signed_in: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const { user, impersonationSessionId } = await requireViewer(ctx);
    // An admin browsing as this user is not the user opening the app.
    if (impersonationSessionId !== null) return null;

    const now = new Date();
    const nowIso = now.toISOString();
    // Only admin screens read it, so the app needs no new revision.
    if (args.signed_in === true) await ctx.db.patch(user._id, { last_sign_in_at: nowIso });
    const hour = new Date(Math.floor(now.getTime() / 3_600_000) * 3_600_000).toISOString();
    const seenThisHour = await ctx.db
      .query("app_activity_hours")
      .withIndex("by_hour_user", (q) => q.eq("hour", hour).eq("user_id", user.id))
      .unique();
    if (seenThisHour === null) {
      await ctx.db.insert("app_activity_hours", { hour, user_id: user.id });
    }

    const fields = {
      app_version: cut(args.app_version, 32),
      build_number: cut(args.build_number, 32),
      os_version: cut(args.os_version, 32),
      device_model: cut(args.device_model, 64),
      locale: cut(args.locale, 64),
      time_zone: cut(args.time_zone, 64),
      app_language: cut(args.app_language, 32),
      notification_permission: cut(args.notification_permission, 32),
      background_refresh: cut(args.background_refresh, 32),
      widget_kinds: args.widget_kinds?.slice(0, 20).map((kind) => kind.slice(0, 64)),
      appearance: cut(args.appearance, 16),
      text_size: cut(args.text_size, 32),
      reduce_motion: args.reduce_motion,
    };

    const row = await ctx.db
      .query("user_app_activity")
      .withIndex("by_user", (q) => q.eq("user_id", user.id))
      .unique();
    if (row === null) {
      await ctx.db.insert("user_app_activity", {
        user_id: user.id,
        first_active_at: nowIso,
        last_active_at: nowIso,
        open_count: 1,
        active_days: 1,
        ...fields,
      });
      return null;
    }

    const versionChanged =
      row.app_version !== fields.app_version || row.build_number !== fields.build_number;
    // Days are counted in Norwegian time, where most users live.
    const newDay = osloDate.format(new Date(row.last_active_at)) < osloDate.format(now);
    await ctx.db.patch(row._id, {
      ...fields,
      last_active_at: nowIso,
      open_count: row.open_count + 1,
      active_days: row.active_days + (newDay ? 1 : 0),
      previous_app_version: versionChanged ? row.app_version : row.previous_app_version,
      previous_build_number: versionChanged ? row.build_number : row.previous_build_number,
    });
    return null;
  },
});
