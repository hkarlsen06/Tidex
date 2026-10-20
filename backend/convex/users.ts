import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import { action, internalMutation, internalQuery, query } from "./_generated/server";
import { getViewer, userByClerkId, userByUuid } from "./lib/auth";
import { deleteClerkUser, getClerkUser } from "./lib/clerk";
import { nextRevision } from "./lib/revision";

/** The signed-in user, or null until `ensureCurrent` has run after sign-in. */
export const current = query({
  args: {},
  handler: async (ctx) => {
    const viewer = await getViewer(ctx);
    if (viewer === null) return null;
    const { user, actor, impersonationSessionId } = viewer;
    return {
      id: user.id,
      email: user.email ?? null,
      name: user.name ?? null,
      avatar_url: user.avatar_url ?? null,
      role: user.role ?? null,
      is_impersonating: impersonationSessionId !== null,
      actor_id: actor.id,
    };
  },
});

/**
 * The app calls this after every sign-in. It returns the user's uuid and creates or
 * links the `users` row on the first sign-in with a new Clerk user.
 */
export const ensureCurrent = action({
  args: {},
  handler: async (ctx): Promise<string> => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) throw new ConvexError({ code: "not_authorized" });

    const existing = await ctx.runQuery(internal.users.idForClerkUser, {
      clerk_user_id: identity.subject,
    });
    if (existing !== null) return existing;

    const clerkUser = await getClerkUser(identity.subject);
    const email = clerkUser.email_addresses.find(
      (e) => e.id === clerkUser.primary_email_address_id,
    )?.email_address;
    const name = [clerkUser.first_name, clerkUser.last_name].filter(Boolean).join(" ");
    const result = await ctx.runMutation(internal.users.linkOrCreate, {
      clerk_user_id: clerkUser.id,
      email: email?.toLowerCase(),
      name: name || undefined,
      avatar_url: clerkUser.has_image ? (clerkUser.image_url ?? undefined) : undefined,
      accounts: clerkUser.external_accounts.map((a) => ({
        provider: a.provider,
        provider_user_id: a.provider_user_id,
      })),
    });
    // ponytail: the imported Clerk user's password and extra emails are lost here. Only
    // users whose Google or Apple email changed since their last Supabase sign-in get
    // this far, and they sign in with that provider. Merge the Clerk users if one reports it.
    if (result.replaced_clerk_user_id !== null) {
      await deleteClerkUser(result.replaced_clerk_user_id);
    }
    return result.id;
  },
});

export const idForClerkUser = internalQuery({
  args: { clerk_user_id: v.string() },
  handler: async (ctx, { clerk_user_id }) => {
    return (await userByClerkId(ctx, clerk_user_id))?.id ?? null;
  },
});

/**
 * Clerk links a Google or Apple sign-in to an imported user only by email. When that
 * fails, Clerk creates a new user, and this matches its provider account against the
 * subs the migration copied from auth.identities. Without a match it creates a new
 * user, like handle_new_user did. Safe to call twice.
 */
export const linkOrCreate = internalMutation({
  args: {
    clerk_user_id: v.string(),
    email: v.optional(v.string()),
    name: v.optional(v.string()),
    avatar_url: v.optional(v.string()),
    accounts: v.array(v.object({ provider: v.string(), provider_user_id: v.string() })),
  },
  handler: async (ctx, args) => {
    const existing = await userByClerkId(ctx, args.clerk_user_id);
    if (existing !== null) return { id: existing.id, replaced_clerk_user_id: null };

    for (const account of args.accounts) {
      const provider = account.provider.replace(/^oauth_/, "");
      if (provider !== "apple" && provider !== "google") continue;
      const legacy = await ctx.db
        .query("legacy_identities")
        .withIndex("by_provider_sub", (q) =>
          q.eq("provider", provider).eq("sub", account.provider_user_id),
        )
        .unique();
      const user = legacy === null ? null : await userByUuid(ctx, legacy.user_id);
      if (user === null) continue;
      await ctx.db.patch(user._id, {
        clerk_user_id: args.clerk_user_id,
        revision: await nextRevision(ctx),
      });
      return { id: user.id, replaced_clerk_user_id: user.clerk_user_id ?? null };
    }

    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    const revision = await nextRevision(ctx);
    await ctx.db.insert("users", {
      id,
      clerk_user_id: args.clerk_user_id,
      email: args.email,
      name: args.name,
      avatar_url: args.avatar_url,
      created_at: now,
      revision,
    });
    await ctx.db.insert("profiles", {
      id,
      before_paywall: true,
      created_at: now,
      updated_at: now,
      revision,
    });
    return { id, replaced_clerk_user_id: null };
  },
});
