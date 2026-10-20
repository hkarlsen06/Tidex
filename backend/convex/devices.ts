import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { type MutationCtx, mutation } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { reject } from "./lib/syncWrite";
import { literals } from "./lib/validators";

// Ports of register_push_device, unregister_my_push_device,
// register_live_activity_device, register_live_activity_update_token and
// end_live_activity_registration.

const HEX_TOKEN = /^[0-9A-Fa-f]{32,512}$/;

function validTimeZone(zone: string) {
  try {
    new Intl.DateTimeFormat("en", { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

async function ownDevices(ctx: MutationCtx, userId: string) {
  return await ctx.db
    .query("push_devices")
    .withIndex("by_user", (q) => q.eq("user_id", userId))
    .collect();
}

const newest = (rows: Doc<"push_devices">[]) =>
  [...rows].sort((a, b) => b.updated_at.localeCompare(a.updated_at) || a.id.localeCompare(b.id))[0];

export const registerPush = mutation({
  args: {
    platform: literals("ios", "android", "web"),
    apns_token: v.optional(v.string()),
    fcm_token: v.optional(v.string()),
    device_id: v.optional(v.string()),
    device_model: v.optional(v.string()),
    app_version: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    const apns = args.apns_token || undefined;
    const fcm = args.fcm_token || undefined;
    if (apns === undefined && fcm === undefined) reject("invalid", "Either apnsToken or fcmToken is required");
    const now = new Date().toISOString();

    // A device token belongs to whoever registered it last.
    if (apns !== undefined) {
      for (const d of await ctx.db
        .query("push_devices")
        .withIndex("by_apns_token", (q) => q.eq("apns_token", apns))
        .collect()) {
        if (d.user_id !== user.id) await ctx.db.delete(d._id);
      }
    }
    const mine = await ownDevices(ctx, user.id);
    const existing =
      (args.device_id !== undefined ? newest(mine.filter((d) => d.device_id === args.device_id)) : undefined) ??
      (fcm !== undefined ? mine.find((d) => d.fcm_token === fcm) : undefined) ??
      (apns !== undefined && fcm === undefined ? newest(mine.filter((d) => d.platform === args.platform)) : undefined);

    if (existing !== undefined) {
      // fcm_token is unique in Postgres, so an update could not take another row's token.
      if (fcm !== undefined && fcm !== existing.fcm_token) {
        const holder = await ctx.db
          .query("push_devices")
          .withIndex("by_fcm_token", (q) => q.eq("fcm_token", fcm))
          .first();
        if (holder !== null) reject("conflict", "fcm token is registered to another device");
      }
      await ctx.db.patch(existing._id, {
        device_id: args.device_id,
        device_model: args.device_model,
        app_version: args.app_version,
        last_seen_at: now,
        updated_at: now,
        apns_environment: apns !== undefined && apns !== existing.apns_token ? undefined : existing.apns_environment,
        apns_token: apns ?? existing.apns_token,
        fcm_token: fcm ?? existing.fcm_token,
      });
      if (args.device_id !== undefined) {
        for (const d of mine) {
          if (d.device_id === args.device_id && d._id !== existing._id) await ctx.db.delete(d._id);
        }
      }
      return { success: true, action: "updated" };
    }

    const fcmToken = fcm ?? `apns_${apns!.slice(0, 32)}`;
    const taken = await ctx.db
      .query("push_devices")
      .withIndex("by_fcm_token", (q) => q.eq("fcm_token", fcmToken))
      .first();
    if (taken !== null) return { success: true, action: "already_registered" };
    await ctx.db.insert("push_devices", {
      id: crypto.randomUUID(),
      user_id: user.id,
      platform: args.platform,
      apns_token: apns,
      fcm_token: fcmToken,
      device_id: args.device_id,
      device_model: args.device_model,
      app_version: args.app_version,
      time_zone: "Europe/Oslo",
      last_seen_at: now,
      created_at: now,
      updated_at: now,
    });
    return { success: true, action: "inserted" };
  },
});

export const unregisterPush = mutation({
  args: { device_token: v.string() },
  handler: async (ctx, { device_token }) => {
    const { user } = await requireViewer(ctx);
    if (device_token === "") return null;
    for (const d of await ownDevices(ctx, user.id)) {
      if (d.apns_token === device_token || d.fcm_token === device_token) await ctx.db.delete(d._id);
    }
    return null;
  },
});

async function deviceFor(ctx: MutationCtx, userId: string, deviceId: string) {
  return newest((await ownDevices(ctx, userId)).filter((d) => d.device_id === deviceId));
}

export const registerLiveActivityDevice = mutation({
  args: {
    device_id: v.string(),
    push_to_start_token: v.string(),
    time_zone: v.string(),
    app_version: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    if (args.device_id.trim() === "") reject("invalid", "device id is required");
    if (!HEX_TOKEN.test(args.push_to_start_token)) reject("invalid", "invalid live activity push-to-start token");
    if (args.time_zone.trim() === "" || !validTimeZone(args.time_zone)) reject("invalid", "invalid IANA time zone");
    const device = await deviceFor(ctx, user.id, args.device_id);
    if (device === undefined) reject("not_found", "push device must be registered before live activities");
    const token = args.push_to_start_token.toLowerCase();
    const holders = (
      await ctx.db
        .query("push_devices")
        .withIndex("by_live_activity_push_to_start_token", (q) => q.eq("live_activity_push_to_start_token", token))
        .collect()
    ).filter((d) => d._id !== device._id);
    if (holders.length > 0) {
      // The same physical device may hold the token under an older row, even for
      // another account. Anything else is a token registered to another device.
      const sameDevice =
        device.live_activity_push_to_start_token === token || holders.some((d) => d.device_id === args.device_id);
      if (!sameDevice) {
        reject("conflict", "live activity token is registered to another device");
      }
      for (const d of holders) {
        await ctx.db.patch(d._id, { live_activity_push_to_start_token: undefined, updated_at: new Date().toISOString() });
      }
    }
    const now = new Date().toISOString();
    await ctx.db.patch(device._id, {
      live_activity_push_to_start_token: token,
      time_zone: args.time_zone,
      app_version: args.app_version ?? device.app_version,
      last_seen_at: now,
      updated_at: now,
    });
    return null;
  },
});

export const registerLiveActivityUpdateToken = mutation({
  args: { device_id: v.string(), shift_id: v.string(), activity_id: v.string(), push_token: v.string() },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    if ([args.device_id, args.shift_id, args.activity_id].some((s) => s.trim() === "")) {
      reject("invalid", "device id, shift id, and activity id are required");
    }
    if (!HEX_TOKEN.test(args.push_token)) reject("invalid", "invalid live activity update token");
    const device = await deviceFor(ctx, user.id, args.device_id);
    if (device === undefined) reject("not_found", "push device not found");
    const token = args.push_token.toLowerCase();
    for (const d of await ctx.db
      .query("live_activity_deliveries")
      .withIndex("by_update_token", (q) => q.eq("update_token", token))
      .collect()) {
      const owner = await ctx.db
        .query("push_devices")
        .withIndex("by_uuid", (q) => q.eq("id", d.push_device_id))
        .unique();
      if (owner !== null && owner.user_id !== user.id) {
        reject("conflict", "live activity update token belongs to another user");
      }
    }
    const now = new Date().toISOString();
    const deliveries = await ctx.db
      .query("live_activity_deliveries")
      .withIndex("by_push_device_shift", (q) => q.eq("push_device_id", device.id))
      .collect();
    // ActivityKit is the source of truth for the current activity on this device.
    for (const d of deliveries) {
      if (d.shift_id !== args.shift_id && ["starting", "active", "ending"].includes(d.status)) {
        await ctx.db.patch(d._id, {
          status: "failed",
          claimed_at: undefined,
          activity_id: undefined,
          update_token: undefined,
          last_error: "Superseded by ActivityKit registration",
          updated_at: now,
        });
      }
    }
    const current = deliveries.find((d) => d.shift_id === args.shift_id);
    const active = {
      status: "active" as const,
      activity_id: args.activity_id,
      update_token: token,
      attempts: 0,
      last_error: undefined,
      claimed_at: undefined,
      updated_at: now,
    };
    if (current === undefined) {
      await ctx.db.insert("live_activity_deliveries", {
        id: crypto.randomUUID(),
        push_device_id: device.id,
        shift_id: args.shift_id,
        active_at: now,
        created_at: now,
        ...active,
      });
    } else {
      await ctx.db.patch(current._id, {
        ...active,
        active_at: current.active_at ?? now,
        ended_at: undefined,
        end_sent_at: undefined,
      });
    }
    return null;
  },
});

export const endLiveActivity = mutation({
  args: { device_id: v.string(), activity_id: v.string() },
  handler: async (ctx, { device_id, activity_id }) => {
    const { user } = await requireViewer(ctx);
    const now = new Date().toISOString();
    for (const device of (await ownDevices(ctx, user.id)).filter((d) => d.device_id === device_id)) {
      for (const d of await ctx.db
        .query("live_activity_deliveries")
        .withIndex("by_push_device_shift", (q) => q.eq("push_device_id", device.id))
        .collect()) {
        if (d.activity_id !== activity_id) continue;
        await ctx.db.patch(d._id, {
          status: "ended",
          claimed_at: undefined,
          ended_at: d.ended_at ?? now,
          last_error: undefined,
          updated_at: now,
        });
      }
    }
    return null;
  },
});
