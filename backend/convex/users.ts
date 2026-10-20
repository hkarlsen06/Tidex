import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import { action, internalMutation, internalQuery, mutation, query } from "./_generated/server";
import { getViewer, requireViewer, userByClerkId, userByUuid } from "./lib/auth";
import { getClerkUser } from "./lib/clerk";
import { queueNewSignup } from "./lib/notify";
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
      terms_accepted_at: user.terms_accepted_at ?? null,
      finished_onboarding: user.finished_onboarding ?? false,
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
    return await ctx.runMutation(internal.users.linkOrCreate, {
      clerk_user_id: clerkUser.id,
      email: email?.toLowerCase(),
      name: name || undefined,
      avatar_url: clerkUser.has_image ? (clerkUser.image_url ?? undefined) : undefined,
      accounts: clerkUser.external_accounts.map((a) => ({
        provider: a.provider,
        provider_user_id: a.provider_user_id,
      })),
    });
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
 * subs the migration copied from auth.identities. On a match the new Clerk user becomes
 * an alias, so the imported Clerk user and its password keep working too. Without a
 * match it creates a new user, like handle_new_user did. Safe to call twice.
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
    if (existing !== null) return existing.id;
    // A Clerk user whose account is being deleted must not sign up again into a new one.
    const deleting = (await ctx.db.query("account_deletions").collect()).some((j) => j.clerk_user_ids.includes(args.clerk_user_id));
    if (deleting) throw new ConvexError({ code: "account_deleted", message: "This account is being deleted" });

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
      if (user.clerk_user_id === undefined) {
        // Phone-only GoTrue users got no Clerk user at import.
        await ctx.db.patch(user._id, {
          clerk_user_id: args.clerk_user_id,
          revision: await nextRevision(ctx),
        });
      } else {
        await ctx.db.insert("clerk_user_aliases", {
          clerk_user_id: args.clerk_user_id,
          user_id: user.id,
          created_at: new Date().toISOString(),
        });
      }
      return user.id;
    }

    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    const revision = await nextRevision(ctx);
    const providers = [
      ...new Set([
        ...args.accounts.map((a) => a.provider.replace(/^oauth_/, "")),
        ...(args.accounts.length === 0 && args.email !== undefined ? ["email"] : []),
      ]),
    ];
    await ctx.db.insert("users", {
      id,
      clerk_user_id: args.clerk_user_id,
      providers,
      email: args.email,
      name: args.name,
      avatar_url: args.avatar_url,
      created_at: now,
      revision,
    });
    await queueNewSignup(ctx, (await userByUuid(ctx, id))!);
    await ctx.db.insert("profiles", {
      id,
      before_paywall: true,
      created_at: now,
      updated_at: now,
      revision: await nextRevision(ctx),
    });
    return id;
  },
});

/**
 * The app's language, for push text. GoTrue kept it in user metadata. The app sends
 * it after sign-in and when the user changes language.
 */
export const setLocale = mutation({
  args: { locale: v.string() },
  handler: async (ctx, { locale }) => {
    const { actor, impersonationSessionId } = await requireViewer(ctx);
    if (impersonationSessionId !== null) return null;
    const value = locale.trim().slice(0, 32);
    if (value !== "" && value !== actor.locale) {
      await ctx.db.patch(actor._id, { locale: value, revision: await nextRevision(ctx) });
    }
    return null;
  },
});

/**
 * The display name from the profile screen. The app also sets it on the Clerk user, which
 * is where friends read it. This keeps `users.current` in step for the app itself.
 */
export const setName = mutation({
  args: { name: v.string() },
  handler: async (ctx, { name }) => {
    const { actor, impersonationSessionId } = await requireViewer(ctx);
    if (impersonationSessionId !== null) return null;
    const value = name.trim().slice(0, 200);
    await ctx.db.patch(actor._id, {
      name: value === "" ? undefined : value,
      revision: await nextRevision(ctx),
    });
    return null;
  },
});

/** Records that the signed-in person accepted the current terms. */
export const acceptTerms = mutation({
  args: {},
  handler: async (ctx) => {
    const { actor, impersonationSessionId } = await requireViewer(ctx);
    if (impersonationSessionId !== null) return null;
    const now = new Date().toISOString();
    await ctx.db.patch(actor._id, { terms_accepted_at: now, revision: await nextRevision(ctx) });
    return now;
  },
});

/** Records that the signed-in user finished onboarding. */
export const finishOnboarding = mutation({
  args: {},
  handler: async (ctx) => {
    const { user } = await requireViewer(ctx);
    if (user.finished_onboarding !== true) {
      await ctx.db.patch(user._id, { finished_onboarding: true, revision: await nextRevision(ctx) });
    }
    return null;
  },
});
