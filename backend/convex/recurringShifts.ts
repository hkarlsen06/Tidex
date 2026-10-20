import { requireLiveJob, syncedTable } from "./lib/syncWrite";

export const { insert, update, remove } = syncedTable("recurring_shifts", {
  check: async (ctx, shift, _prev, changed) => {
    if (changed.has("job_id")) await requireLiveJob(ctx, shift.user_id, shift.job_id);
  },
});
