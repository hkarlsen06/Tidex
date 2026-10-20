import { ConvexError } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";

export type Viewer = {
  /** The user whose data the request reads and writes. During impersonation, the target. */
  user: Doc<"users">;
  /** The signed-in user. Differs from `user` only while an admin impersonates someone. */
  actor: Doc<"users">;
  impersonationSessionId: string | null;
};

export async function userByUuid(ctx: QueryCtx, id: string): Promise<Doc<"users"> | null> {
  return await ctx.db
    .query("users")
    .withIndex("by_uuid", (q) => q.eq("id", id))
    .unique();
}

/** Finds the user by their main Clerk user, or by one in clerk_user_aliases. */
export async function userByClerkId(
  ctx: QueryCtx,
  clerkUserId: string,
): Promise<Doc<"users"> | null> {
  const user = await ctx.db
    .query("users")
    .withIndex("by_clerk_user_id", (q) => q.eq("clerk_user_id", clerkUserId))
    .unique();
  if (user !== null) return user;
  const alias = await ctx.db
    .query("clerk_user_aliases")
    .withIndex("by_clerk_user_id", (q) => q.eq("clerk_user_id", clerkUserId))
    .unique();
  return alias === null ? null : await userByUuid(ctx, alias.user_id);
}

/**
 * Returns null when signed out, banned, or before `users.ensureCurrent` has created the
 * row. While an admin has an active impersonation session, `user` is the target.
 */
export async function getViewer(ctx: QueryCtx): Promise<Viewer | null> {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) return null;
  const actor = await userByClerkId(ctx, identity.subject);
  if (actor === null || actor.banned_at !== undefined) return null;

  if (actor.role === "admin") {
    const session = await ctx.db
      .query("impersonation_sessions")
      .withIndex("by_admin_ended_at", (q) =>
        q.eq("admin_user_id", actor.id).eq("ended_at", undefined),
      )
      .order("desc")
      .first();
    // Subscriptions don't rerun when time passes. impersonation.start schedules
    // impersonation.expire to set ended_at at expires_at, and this check covers a
    // query that runs between the two.
    if (session !== null && Date.parse(session.expires_at) > Date.now()) {
      const target = await userByUuid(ctx, session.target_user_id);
      if (target !== null) {
        return { user: target, actor, impersonationSessionId: session.id };
      }
    }
  }
  return { user: actor, actor, impersonationSessionId: null };
}

export async function requireViewer(ctx: QueryCtx): Promise<Viewer> {
  const viewer = await getViewer(ctx);
  if (viewer === null) throw new ConvexError({ code: "not_authorized" });
  return viewer;
}
