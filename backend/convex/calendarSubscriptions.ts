import { v } from "convex/values";
import { type MutationCtx, mutation, type QueryCtx, query } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { reject } from "./lib/syncWrite";
import { literals } from "./lib/validators";

// Ports of get_my_calendar_subscription, create_my_calendar_subscription,
// disable_my_calendar_subscription and set_my_calendar_subscription_content_mode. Only
// the SHA-256 of the feed token is stored, in the same hex form as Postgres, so the
// calendar feed can keep looking tokens up by hash after the migration.

const contentMode = literals("events_only", "shifts_only", "shifts_and_events");

const hex = (bytes: ArrayBuffer | Uint8Array) =>
  [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");

export async function hashCalendarToken(raw: string) {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw)));
}

async function activeToken(ctx: QueryCtx, userId: string) {
  return (
    await ctx.db
      .query("calendar_subscription_tokens")
      .withIndex("by_user", (q) => q.eq("user_id", userId))
      .collect()
  )
    .filter((t) => t.revoked_at === undefined)
    .sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
}

function status(token: Awaited<ReturnType<typeof activeToken>>) {
  return token === undefined
    ? { is_active: false, id: null, content_mode: null, token_suffix: null, created_at: null, updated_at: null, last_used_at: null }
    : {
        is_active: true,
        id: token.id,
        content_mode: token.content_mode,
        token_suffix: token.token_suffix,
        created_at: token.created_at,
        updated_at: token.updated_at,
        last_used_at: token.last_used_at ?? null,
      };
}

export const get = query({
  args: {},
  handler: async (ctx) => {
    const { user } = await requireViewer(ctx);
    return status(await activeToken(ctx, user.id));
  },
});

/** Returns the raw token once. Only its hash is kept. */
export const create = mutation({
  args: { content_mode: v.optional(contentMode) },
  handler: async (ctx, { content_mode }) => {
    const { user } = await requireViewer(ctx);
    if ((await activeToken(ctx, user.id)) !== undefined) {
      reject("already_exists", "active calendar subscription already exists");
    }
    const raw = `tidex_cal_${hex(crypto.getRandomValues(new Uint8Array(32)))}`;
    const now = new Date().toISOString();
    const id = crypto.randomUUID();
    const mode = content_mode ?? "shifts_only";
    const suffix = raw.slice(-8);
    await ctx.db.insert("calendar_subscription_tokens", {
      id,
      user_id: user.id,
      token_hash: await hashCalendarToken(raw),
      token_suffix: suffix,
      content_mode: mode,
      created_at: now,
      updated_at: now,
    });
    return { id, raw_token: raw, content_mode: mode, token_suffix: suffix, created_at: now };
  },
});

async function revokeAll(ctx: MutationCtx, userId: string) {
  const now = new Date().toISOString();
  const tokens = await ctx.db
    .query("calendar_subscription_tokens")
    .withIndex("by_user", (q) => q.eq("user_id", userId))
    .collect();
  let revoked = 0;
  for (const t of tokens) {
    if (t.revoked_at !== undefined) continue;
    await ctx.db.patch(t._id, { revoked_at: now, updated_at: now });
    revoked += 1;
  }
  return revoked;
}

export const disable = mutation({
  args: {},
  handler: async (ctx) => {
    const { user } = await requireViewer(ctx);
    return (await revokeAll(ctx, user.id)) > 0;
  },
});

export const setContentMode = mutation({
  args: { content_mode: contentMode },
  handler: async (ctx, { content_mode }) => {
    const { user } = await requireViewer(ctx);
    const token = await activeToken(ctx, user.id);
    if (token === undefined) reject("not_found", "no active calendar subscription");
    await ctx.db.patch(token._id, { content_mode, updated_at: new Date().toISOString() });
    return status((await ctx.db.get(token._id))!);
  },
});
