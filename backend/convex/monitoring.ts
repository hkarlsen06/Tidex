import { internalQuery } from "./_generated/server";

const UPTIME_OWNER = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";

export const health = internalQuery({
  args: {},
  handler: async (ctx) => {
    await ctx.db.query("users").first();
    return { ok: true };
  },
});

export const uptimeDevices = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("push_devices").withIndex("by_user", (q) => q.eq("user_id", UPTIME_OWNER)).collect();
    return {
      owner_id: UPTIME_OWNER,
      source: "convex",
      exported_at: new Date().toISOString(),
      devices: rows.flatMap((device) =>
        device.platform === "ios" && device.device_model === "iPhone" && device.apns_token
          ? [{ token: device.apns_token, environment: device.apns_environment ?? null }]
          : [],
      ),
    };
  },
});
