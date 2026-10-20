import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, type MutationCtx, mutation, type QueryCtx, query } from "./_generated/server";
import { requireViewer, userByUuid } from "./lib/auth";

// Port of the impersonation Edge Function. The admin stays signed in as themselves.
// While their session is open and not expired, lib/auth.ts getViewer returns the target,
// so every query and mutation acts as the target. No magic link, target session or
// stored admin token is needed.

const SUPERADMIN_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
const SESSION_MS = 60 * 60_000;
const STARTS_PER_HOUR = 10;

const fail = (message: string): never => {
  throw new ConvexError({ code: "impersonation", message });
};

async function openSessionFor(ctx: QueryCtx, adminId: string) {
  return await ctx.db
    .query("impersonation_sessions")
    .withIndex("by_admin_ended_at", (q) => q.eq("admin_user_id", adminId).eq("ended_at", undefined))
    .order("desc")
    .first();
}

async function audit(
  ctx: MutationCtx,
  session: Doc<"impersonation_sessions">,
  action: "start" | "stop" | "session_expired",
  extra: { reason?: string; metadata?: Record<string, unknown> } = {},
) {
  await ctx.db.insert("impersonation_audit_log", {
    id: crypto.randomUUID(),
    session_id: session.id,
    admin_user_id: session.admin_user_id,
    target_user_id: session.target_user_id,
    action,
    reason: extra.reason,
    metadata: extra.metadata,
    created_at: new Date().toISOString(),
  });
}

async function end(ctx: MutationCtx, session: Doc<"impersonation_sessions">, endedBy: string | undefined) {
  await ctx.db.patch(session._id, { ended_at: new Date().toISOString(), ended_by_admin_user_id: endedBy });
}

const sessionJson = (s: Doc<"impersonation_sessions">) => ({
  id: s.id,
  admin_user_id: s.admin_user_id,
  target_user_id: s.target_user_id,
  reason: s.reason,
  created_at: s.created_at,
  expires_at: s.expires_at,
});

export const start = mutation({
  args: { target_user_id: v.string(), reason: v.string() },
  handler: async (ctx, { target_user_id, reason }) => {
    const { actor, impersonationSessionId } = await requireViewer(ctx);
    if (actor.role !== "admin") fail("Admin access required");
    if (impersonationSessionId !== null) fail("Nested impersonation is not allowed");
    const targetedByOthers = (await ctx.db.query("impersonation_sessions").collect()).some(
      (s) => s.target_user_id === actor.id && s.ended_at === undefined && Date.parse(s.expires_at) > Date.now(),
    );
    if (targetedByOthers) fail("Nested impersonation is not allowed");
    if (reason.trim().length < 5) fail("reason is required (minimum 5 characters)");
    if (target_user_id === actor.id) fail("Cannot impersonate yourself");

    const hourAgo = new Date(Date.now() - 3_600_000).toISOString();
    const recent = await ctx.db
      .query("impersonation_sessions")
      .withIndex("by_admin_created_at", (q) => q.eq("admin_user_id", actor.id).gte("created_at", hourAgo))
      .collect();
    if (recent.length >= STARTS_PER_HOUR) fail("Rate limit exceeded. Maximum 10 impersonation attempts per hour.");

    const open = await openSessionFor(ctx, actor.id);
    if (open !== null) {
      await end(ctx, open, actor.id);
      await audit(ctx, open, "stop", { metadata: { ended_by_type: "admin", reason: "replaced" } });
    }
    const target = await userByUuid(ctx, target_user_id);
    if (target === null) fail("Target user not found");
    if (target!.role === "admin" && actor.id !== SUPERADMIN_USER_ID) fail("Cannot impersonate admin users");

    const now = Date.now();
    const id = crypto.randomUUID();
    const docId = await ctx.db.insert("impersonation_sessions", {
      id,
      admin_user_id: actor.id,
      target_user_id,
      reason: reason.trim(),
      created_at: new Date(now).toISOString(),
      expires_at: new Date(now + SESSION_MS).toISOString(),
    });
    const session = (await ctx.db.get(docId))!;
    await audit(ctx, session, "start", { reason: session.reason, metadata: { target_email: target!.email ?? null } });
    // Ending at expiry writes ended_at, so subscriptions rerun and the admin is back.
    await ctx.scheduler.runAt(now + SESSION_MS, internal.impersonation.expire, { session_id: id });
    return { ok: true, session: sessionJson(session) };
  },
});

/** Ends a session. The admin who started it or the impersonated user can end it. */
export const stop = mutation({
  args: { session_id: v.string() },
  handler: async (ctx, { session_id }) => {
    const { actor } = await requireViewer(ctx);
    const session = await ctx.db
      .query("impersonation_sessions")
      .withIndex("by_uuid", (q) => q.eq("id", session_id))
      .unique();
    if (session === null) fail("Session not found");
    if (session!.admin_user_id !== actor.id && session!.target_user_id !== actor.id) fail("Not authorized to end this session");
    if (session!.ended_at !== undefined) fail("Session already ended");
    await end(ctx, session!, session!.admin_user_id === actor.id ? actor.id : undefined);
    await audit(ctx, session!, "stop", { metadata: { ended_by_type: session!.admin_user_id === actor.id ? "admin" : "target" } });
    return { ok: true };
  },
});

export const expire = internalMutation({
  args: { session_id: v.string() },
  handler: async (ctx, { session_id }) => {
    const session = await ctx.db
      .query("impersonation_sessions")
      .withIndex("by_uuid", (q) => q.eq("id", session_id))
      .unique();
    if (session === null || session.ended_at !== undefined) return;
    await end(ctx, session, undefined);
    await audit(ctx, session, "session_expired");
  },
});

/** The admin's open session, for the app's impersonation banner. */
export const active = query({
  args: {},
  handler: async (ctx) => {
    const { actor } = await requireViewer(ctx);
    const session = await openSessionFor(ctx, actor.id);
    return session === null || Date.parse(session.expires_at) <= Date.now() ? null : sessionJson(session);
  },
});
