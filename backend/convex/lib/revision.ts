import type { MutationCtx } from "../_generated/server";

/**
 * Returns the next revision. Call it once for every row a mutation writes, so no two
 * rows share a revision. Pages end at a row, and with shared revisions the next page's
 * `revision > cursor` would skip the rest of a group, such as a job's cascaded snapshots.
 *
 * Every mutation that calls this reads and writes the same counter document, so Convex
 * commits them one at a time in revision order. A query that sees revision N therefore
 * also sees every row with a lower revision, and `revision > cursor` never skips a row.
 */
// ponytail: one counter for the whole deployment. Every writing mutation conflicts on it
// and Convex retries the loser. Move to per-user counters if retries show up in the logs.
export async function nextRevision(ctx: MutationCtx): Promise<number> {
  const counter = await ctx.db.query("revision_counter").unique();
  if (counter === null) {
    await ctx.db.insert("revision_counter", { value: 1 });
    return 1;
  }
  const value = counter.value + 1;
  await ctx.db.patch(counter._id, { value });
  return value;
}
