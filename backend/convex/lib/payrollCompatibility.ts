import { ConvexError } from "convex/values";
import type { MutationCtx } from "../_generated/server";

export const PAYROLL_REVISION = "2026-11";
const ruleFields = new Set([
  "stackingGroup",
  "dates",
  "excludedDates",
  "shiftStartDates",
  "shiftStartBefore",
  "excludedShiftStartDates",
  "minimumRate",
  "percentageBaseRate",
  "retainedSupplements",
]);

export function needsReviewedPayroll(value: unknown): boolean {
  if (value === null || typeof value !== "object") return false;
  if (Array.isArray(value)) return value.some(needsReviewedPayroll);
  return Object.entries(value).some(
    ([key, item]) =>
      (ruleFields.has(key) && item !== undefined && item !== null) ||
      (key === "retainSupplements" && item === true) ||
      (key === "baseRate" &&
        typeof item === "number" &&
        "weeklyThresholdHours" in value) ||
      (key === "premiumBaseMultiplier" &&
        typeof item === "number" &&
        item !== 1) ||
      needsReviewedPayroll(item),
  );
}

export function requirePayrollRevision(
  revision: string | undefined,
  value: unknown,
): void {
  if (revision !== PAYROLL_REVISION && needsReviewedPayroll(value)) {
    throw new ConvexError({
      code: "payroll_update_required",
      message:
        "Update Tidex to use this job's tariff rules. Your saved pay settings have not changed.",
    });
  }
}

export async function requireCompatibleJob(
  ctx: MutationCtx,
  userId: string,
  table: string,
  row: Record<string, unknown>,
  revision?: string,
): Promise<void> {
  if (revision === PAYROLL_REVISION) return;
  requirePayrollRevision(revision, row);
  const jobId = table === "jobs" ? row.id : row.job_id;
  if (
    typeof jobId !== "string" ||
    !["jobs", "user_shifts", "recurring_shifts", "wage_snapshots"].includes(
      table,
    )
  )
    return;
  const snapshots = await ctx.db
    .query("wage_snapshots")
    .withIndex("by_user_job_from_date", (q) =>
      q.eq("user_id", userId).eq("job_id", jobId),
    )
    .collect();
  requirePayrollRevision(
    revision,
    snapshots.filter((snapshot) => snapshot.deleted_at === undefined),
  );
}
