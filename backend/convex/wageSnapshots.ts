import { reject, requireLiveJob, syncedTable } from "./lib/syncWrite";

export const { insert, update, remove } = syncedTable("wage_snapshots", {
  check: async (ctx, snapshot, _prev, changed) => {
    if (changed.has("job_id")) await requireLiveJob(ctx, snapshot.user_id, snapshot.job_id);
    const tax = snapshot.tax_percentage;
    if (tax !== undefined && !(tax >= 0 && tax <= 100)) {
      reject("invalid_row", "wage_snapshots_tax_percentage_check");
    }
    // idx_wage_snapshots_baseline and idx_wage_snapshots_unique_date: one live snapshot
    // per job and from_date, where a missing from_date is the job's baseline.
    if (snapshot.deleted_at === undefined) {
      const clash = await ctx.db
        .query("wage_snapshots")
        .withIndex("by_user_job_from_date", (q) =>
          q
            .eq("user_id", snapshot.user_id)
            .eq("job_id", snapshot.job_id)
            .eq("from_date", snapshot.from_date),
        )
        .filter((q) => q.and(q.neq(q.field("id"), snapshot.id), q.eq(q.field("deleted_at"), undefined)))
        .first();
      if (clash !== null) reject("wage_snapshot_exists");
    }
  },
});
