import { ConvexError } from "convex/values";
import type { Doc } from "../../_generated/dataModel";
import type { QueryCtx } from "../../_generated/server";
import { userByUuid } from "../auth";
import { ToolError } from "./shiftTimes";

// Database helpers the MCP tool modules (mcp<Area>.ts) share.

/** The fixed window mcp_rate_limits counts calls in. */
export const RATE_WINDOW_MS = 10 * 60_000;

/** A message the agent sees as the tool's result. */
export function fail(message: string): never {
  throw new ConvexError({ code: "tool_error", message });
}

/** Runs a helper, turning its ToolError into a message the agent sees. */
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

/** Formats available jobs into a short hint when a lookup misses or is ambiguous. */
function jobListHint(jobs: Doc<"jobs">[]): string {
  if (jobs.length === 0) return "The user has no jobs yet. Add one with save_job first.";
  const list = jobs.map((j) => `${j.name} (${j.id})`).join(", ");
  return `Available jobs: ${list}.`;
}

/**
 * Resolves a job by ID or case-insensitive name. When `ref` is omitted, picks the
 * default active job (or first active job).
 */
export function matchJob(
  jobs: Doc<"jobs">[],
  ref: string | undefined,
  options: { includeArchived?: boolean } = {},
): Doc<"jobs"> {
  const pool = options.includeArchived ? jobs : activeJobs(jobs);
  if (ref === undefined) {
    const active = activeJobs(jobs);
    const chosen = active.find((j) => j.is_default) ?? active[0];
    if (chosen === undefined) fail("The user has no jobs yet. Add one with save_job first.");
    return chosen;
  }
  const trimmed = ref.trim();
  const byId = pool.find((j) => j.id === trimmed);
  if (byId !== undefined) return byId;
  const lower = trimmed.toLowerCase();
  const byName = pool.filter((j) => j.name.trim().toLowerCase() === lower);
  if (byName.length === 1) return byName[0]!;
  if (byName.length > 1) {
    const choices = byName.map((j) => `${j.name} (${j.id})`).join(", ");
    fail(`Multiple jobs match "${trimmed}". Pass the exact job ID instead: ${choices}.`);
  }
  fail(`No ${options.includeArchived ? "" : "active "}job matches "${trimmed}". ${jobListHint(pool)}`);
}

/** A live, unarchived job of the user's with pay set up: matched by ID or name, else default. */
export async function jobForShift(ctx: QueryCtx, userId: string, jobRef: string | undefined) {
  const jobs = await jobsOf(ctx, userId);
  const job = matchJob(jobs, jobRef, { includeArchived: false });
  if (!(await jobsWithPay(ctx, userId)).has(job.id)) {
    fail(`Set up pay for ${job.name} with set_pay first.`);
  }
  return job;
}

export async function requireUser(ctx: QueryCtx, userId: string) {
  const user = await userByUuid(ctx, userId);
  if (user === null || user.banned_at !== undefined) fail("This Tidex account is not available.");
  return user;
}
