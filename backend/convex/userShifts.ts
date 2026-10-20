import { requireLiveJob, syncedTable } from "./lib/syncWrite";

// The shift-added notification to friends (queue_shift_added_notification and its
// cancel on delete) moves to Convex with the other notifications in phase 1, step 5.
export const { insert, update, remove } = syncedTable("user_shifts", {
  check: async (ctx, shift, _prev, changed) => {
    if (changed.has("job_id")) await requireLiveJob(ctx, shift.user_id, shift.job_id);
  },
});
