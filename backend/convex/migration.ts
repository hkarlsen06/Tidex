import { v } from "convex/values";
import { internalAction, internalMutation, internalQuery } from "./_generated/server";

// Helpers for scripts/migrate.ts, which runs them with the deployment's admin key.

/** Upload URLs for the files the migration copies from Supabase Storage. */
export const uploadUrls = internalAction({
  args: { count: v.number() },
  handler: async (ctx, { count }) => await Promise.all(Array.from({ length: count }, () => ctx.storage.generateUploadUrl())),
});

/**
 * Deletes up to 500 stored files and returns how many. The migration runs it before
 * copying, so a rerun replaces the last copy's files instead of leaving them behind.
 */
export const deleteFiles = internalMutation({
  args: {},
  handler: async (ctx) => {
    const files = await ctx.db.system.query("_storage").take(500);
    for (const f of files) await ctx.storage.delete(f._id);
    return files.length;
  },
});

/** Row counts, to compare with Postgres when the migration finishes. */
export const count = internalQuery({
  args: { table: v.string() },
  handler: async (ctx, { table }) => {
    let n = 0;
    for await (const _ of (ctx.db as any).query(table)) n += 1;
    return n;
  },
});
