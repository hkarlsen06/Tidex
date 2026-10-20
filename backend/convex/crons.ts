import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Queueing a push schedules the sender for its due time. This catches anything a
// schedule missed, like process-pending-push-notifications did once a minute.
crons.interval("push notifications", { minutes: 1 }, internal.push.run, {});

export default crons;
