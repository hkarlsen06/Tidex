import { cancelShiftAdded, queueShiftAdded } from "./lib/notify";
import { requireLiveJob, syncedTable } from "./lib/syncWrite";

const shifts = syncedTable("user_shifts", {
  check: async (ctx, shift, _prev, changed) => {
    if (changed.has("job_id")) await requireLiveJob(ctx, shift.user_id, shift.job_id);
  },
  // queue_shift_added_notification and cancel_shift_added_notification_for_deleted_shift
  afterInsert: queueShiftAdded,
  afterRemove: cancelShiftAdded,
});

export const { insert, update, remove } = shifts;
/** The same writes for a known user, for the MCP server. */
export const shiftWrites = { insert: shifts.insertFor, update: shifts.updateFor, remove: shifts.removeFor };
