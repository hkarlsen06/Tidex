import type { Doc } from "./_generated/dataModel";
import type { MutationCtx } from "./_generated/server";
import { chars, reject, syncedTable } from "./lib/syncWrite";

const PAY_START_DAY = /^([1-9]|1[0-9]|2[0-8])$/;
const PAYOUT_MONTH_OFFSET = /^[01]$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const PAYOUT_DELAY_DAYS = /^([0-9]|1[0-9]|2[0-7])$/;

/** jobs_pay_period_valid. Postgres compares the values as text, so 5 and "5" both pass. */
function validPayPeriod(value: unknown): boolean {
  if (value === undefined) return true;
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const p = value as Record<string, unknown>;
  const text = (k: string) => (typeof p[k] === "string" || typeof p[k] === "number" ? String(p[k]) : "");
  const keys = Object.keys(p).sort().join(",");
  if (p.type === "monthly") {
    return (
      keys === "payoutMonthOffset,startDay,type" &&
      PAY_START_DAY.test(text("startDay")) &&
      PAYOUT_MONTH_OFFSET.test(text("payoutMonthOffset"))
    );
  }
  if (p.type === "biweekly") {
    return (
      keys === "anchorEnd,payoutDelayDays,type" &&
      ISO_DATE.test(text("anchorEnd")) &&
      PAYOUT_DELAY_DAYS.test(text("payoutDelayDays"))
    );
  }
  return false;
}

const isLive = (job: Doc<"jobs">) => job.deleted_at === undefined && job.archived_at === undefined;

async function userJobs(ctx: MutationCtx, userId: string) {
  return await ctx.db
    .query("jobs")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .collect();
}

async function userSettings(ctx: MutationCtx, userId: string) {
  return await ctx.db
    .query("user_settings")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .unique();
}

export const { insert, update, remove } = syncedTable(
  "jobs",
  {
    defaults: async (ctx, userId) => ({
      is_default: false,
      sort_order: 0,
      payroll_day: 15,
      monthly_goal: 20000,
      currency: (await userSettings(ctx, userId))?.currency ?? "kr",
    }),

    check: async (ctx, job, prev) => {
      if (chars(job.name) < 1 || chars(job.name) > 100) reject("invalid_row", "jobs_name_check");
      if (job.color !== undefined && !/^#[0-9a-fA-F]{6}$/.test(job.color)) {
        reject("invalid_row", "jobs_color_check");
      }
      if (job.payroll_day !== undefined && !(job.payroll_day >= 1 && job.payroll_day <= 31)) {
        reject("invalid_row", "jobs_payroll_day_check");
      }
      if (!validPayPeriod(job.pay_period)) reject("invalid_row", "jobs_pay_period_valid");
      if (prev !== null && prev.currency !== job.currency) reject("currency_immutable");
      // idx_jobs_default: one live default job per user.
      if (job.is_default && isLive(job)) {
        const other = (await userJobs(ctx, job.user_id)).find(
          (j) => j.id !== job.id && j.is_default && isLive(j),
        );
        if (other !== undefined) reject("default_job_exists");
      }
    },

    // sync_default_job_to_legacy_settings: the default job's pay settings live in
    // user_settings too, for older code that still reads them there.
    afterWrite: async (ctx, job, changed, revision) => {
      const mirrored = ["payroll_day", "half_tax_month", "monthly_goal", "is_default", "currency"];
      if (!job.is_default || !mirrored.some((k) => changed.has(k))) return;
      const settings = await userSettings(ctx, job.user_id);
      if (settings === null) return;
      await ctx.db.patch(settings._id, {
        payroll_day: job.payroll_day,
        half_tax_month: job.half_tax_month,
        monthly_goal: job.monthly_goal,
        currency: job.currency,
        updated_at: new Date().toISOString(),
        revision,
      });
    },

    // prevent_job_delete_with_active_dependents
    beforeRemove: async (ctx, job) => {
      const live = <R extends { deleted_at?: string }>(rows: R[]) =>
        rows.some((r) => r.deleted_at === undefined);
      const byJob = (t: "user_shifts" | "recurring_shifts" | "payroll_adjustments") =>
        ctx.db
          .query(t)
          .withIndex("by_job", (q) => q.eq("job_id", job.id))
          .collect();
      if (live(await byJob("user_shifts"))) {
        reject("job_has_active_dependents", "cannot delete job with active shifts");
      }
      if (live(await byJob("recurring_shifts"))) {
        reject("job_has_active_dependents", "cannot delete job with active recurring shifts");
      }
      if (live(await byJob("payroll_adjustments"))) {
        reject("job_has_active_dependents", "cannot delete job with active payroll adjustments");
      }
    },

    // set_wage_snapshots_deleted_at_from_job
    afterRemove: async (ctx, job, revision) => {
      const snapshots = await ctx.db
        .query("wage_snapshots")
        .withIndex("by_job", (q) => q.eq("job_id", job.id))
        .collect();
      for (const s of snapshots) {
        if (s.deleted_at === job.deleted_at) continue;
        await ctx.db.patch(s._id, { deleted_at: job.deleted_at, updated_at: job.updated_at, revision });
      }
    },

    removePatch: { is_default: false },
  },
  ["is_default", "sort_order", "currency"],
);
