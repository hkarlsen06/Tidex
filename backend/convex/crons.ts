import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Queueing a push schedules the sender for its due time. This catches anything a
// schedule missed, like process-pending-push-notifications did once a minute.
crons.interval("push notifications", { minutes: 1 }, internal.push.run, {});

// process-live-activities: starts and ends Live Activities for shifts in progress.
crons.cron("live activities", "1,16,31,46 * * * *", internal.liveActivities.run, {});

// The pg_cron purges, at the same UTC times.
crons.cron("purge soft deletes", "30 3 * * *", internal.maintenance.purgeSoftDeletes, {});
crons.cron("clean up outbox", "0 4 * * 0", internal.maintenance.cleanupOutbox, {});
crons.cron("purge auth diagnostics", "45 4 * * 0", internal.maintenance.purgeDiagnostics, {});
crons.cron("purge app activity hours", "50 4 * * *", internal.maintenance.purgeActivityHours, {});
crons.cron("purge stale typing and uploads", "10 * * * *", internal.maintenance.purgeStaleMessagingRows, {});

export default crons;
