import { ConvexError } from "convex/values";
import type { Doc } from "../../_generated/dataModel";
import type { QueryCtx } from "../../_generated/server";
import { userByUuid } from "../auth";
import { ToolError } from "./shiftTimes";

// Database helpers the MCP tool modules (mcp<Area>.ts) share.

/** A message the agent sees as the tool's result. */
export function fail(message: string): never {
  throw new ConvexError({ code: "tool_error", message });
}

/** Runs a shift-time helper, turning its ToolError into a message the agent sees. */
export function checked<T>(run: () => T): T {
  try {
    return run();
  } catch (error) {
    if (error instanceof ToolError) fail(error.message);
    throw error;
  }
}

export const live = <T extends { deleted_at?: string }>(rows: T[]) => rows.filter((r) => r.deleted_at === undefined);

export async function jobsOf(ctx: QueryCtx, userId: string) {
  return live(await ctx.db.query("jobs").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect());
}

/** Jobs with a base wage snapshot, which the app requires before it adds shifts. */
export async function jobsWithPay(ctx: QueryCtx, userId: string) {
  const snapshots = live(
    await ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect(),
  );
  return new Set(snapshots.filter((s) => s.from_date === undefined).map((s) => s.job_id));
}

export const activeJobs = (jobs: Doc<"jobs">[]) =>
  jobs.filter((j) => j.archived_at === undefined).sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name));

/** A live, unarchived job of the user's with pay set up: the given one, else the default, else the first. */
export async function jobForShift(ctx: QueryCtx, userId: string, jobId: string | undefined) {
  const jobs = activeJobs(await jobsOf(ctx, userId));
  const job = jobId === undefined ? (jobs.find((j) => j.is_default) ?? jobs[0]) : jobs.find((j) => j.id === jobId);
  if (job === undefined) {
    fail(jobId === undefined ? "The user has no jobs yet. Add one in the Tidex app first." : "No active job with that job_id. Use list_jobs.");
  }
  if (!(await jobsWithPay(ctx, userId)).has(job.id)) fail(`Set up pay for ${job.name} in the Tidex app first.`);
  return job;
}

export async function requireUser(ctx: QueryCtx, userId: string) {
  const user = await userByUuid(ctx, userId);
  if (user === null || user.banned_at !== undefined) fail("This Tidex account is not available.");
  return user;
}
