import { requireLiveJob, syncedTable } from "./lib/syncWrite";

const recurring = syncedTable("recurring_shifts", {
  check: async (ctx, shift, _prev, changed) => {
    if (changed.has("job_id")) await requireLiveJob(ctx, shift.user_id, shift.job_id);
  },
});

export const { insert, update, remove } = recurring;
/** The same writes for a known user, for the MCP server. */
export const recurringWrites = { insert: recurring.insertFor, update: recurring.updateFor, remove: recurring.removeFor };
