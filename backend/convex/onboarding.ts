import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { reject } from "./lib/syncWrite";

const STEP = /^[a-z][A-Za-z0-9_]{0,63}$/;
const PREAUTH_STEP = /^[a-z][a-z0-9_]{0,63}$/;
const PREAUTH_LIMIT_PER_HOUR = 1000;

/** The upsert into onboarding_funnel_steps. A step already recorded keeps its first time. */
export const recordSteps = mutation({
  args: { steps: v.array(v.object({ step: v.string(), reached_at: v.optional(v.string()) })) },
  handler: async (ctx, { steps }) => {
    const { user, impersonationSessionId } = await requireViewer(ctx);
    if (impersonationSessionId !== null) return null;
    const now = new Date().toISOString();
    for (const { step, reached_at } of steps) {
      if (!STEP.test(step)) reject("invalid", "Invalid onboarding step");
      const existing = await ctx.db
        .query("onboarding_funnel_steps")
        .withIndex("by_user_step", (q) => q.eq("user_id", user.id).eq("step", step))
        .unique();
      if (existing !== null) continue;
      const reached = reached_at === undefined ? Number.NaN : Date.parse(reached_at);
      await ctx.db.insert("onboarding_funnel_steps", {
        user_id: user.id,
        step,
        reached_at: Number.isNaN(reached) ? now : new Date(reached).toISOString(),
        recorded_at: now,
      });
    }
    return null;
  },
});

/**
 * Port of record_onboarding_preauth_step. Needs no sign-in, so anyone can call it with
 * made-up install ids. The hourly cap bounds the writes, and the app keeps a refused
 * step and retries it with the next page.
 */
export const recordPreauthStep = mutation({
  args: { install_id: v.string(), step: v.string(), reached_at: v.optional(v.string()) },
  handler: async (ctx, { install_id, step, reached_at }) => {
    if (!/^[0-9a-f-]{36}$/i.test(install_id) || !PREAUTH_STEP.test(step)) {
      reject("invalid", "Invalid onboarding step");
    }
    const now = new Date();
    const hourAgo = new Date(now.getTime() - 3_600_000).toISOString();
    const lastHour = await ctx.db
      .query("onboarding_preauth_steps")
      .withIndex("by_recorded_at", (q) => q.gte("recorded_at", hourAgo))
      .take(PREAUTH_LIMIT_PER_HOUR);
    if (lastHour.length >= PREAUTH_LIMIT_PER_HOUR) reject("rate_limited", "Onboarding step rate limit exceeded");
    const installId = install_id.toLowerCase();
    const existing = await ctx.db
      .query("onboarding_preauth_steps")
      .withIndex("by_install_step", (q) => q.eq("install_id", installId).eq("step", step))
      .unique();
    if (existing !== null) return null;
    const reached = reached_at === undefined ? Number.NaN : Date.parse(reached_at);
    await ctx.db.insert("onboarding_preauth_steps", {
      install_id: installId,
      step,
      reached_at: new Date(Number.isNaN(reached) ? now.getTime() : Math.min(reached, now.getTime())).toISOString(),
      recorded_at: now.toISOString(),
    });
    return null;
  },
});
