import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import { deleteArchivedFor, jobWrites } from "./jobs";
import { activeJobs, checked, fail, jobsOf, jobsWithPay, live, requireUser } from "./lib/mcp/db";
import * as specs from "./lib/mcp/pay";
import {
  archiveRefusal,
  getTariff,
  jobRow,
  jobView,
  listTariffs,
  type PaySettings,
  payView,
  placement,
  snapshotFields,
  snapshotInEffect,
  snapshotRow,
  snapshotUpdate,
} from "./lib/mcp/pay";
import { type McpTool, tool } from "./lib/mcp/registry";
import { PAYROLL_REVISION } from "./lib/payrollCompatibility";
import { wageSnapshotWrites } from "./wageSnapshots";

// The MCP job, pay and tariff tools. Each runs for the user the OAuth token names; mcp.ts
// checks the token, the scope and the arguments first. None of these functions is public.

const JOB_STALE = "The job changed since you listed it. Call list_jobs again and use the new revision.";
const PAY_STALE = "The pay changed since you read it. Call get_pay again and use the new revision.";

async function ownJob(ctx: QueryCtx, userId: string, jobId: string) {
  const job = (await jobsOf(ctx, userId)).find((j) => j.id === jobId);
  if (job === undefined) fail("No job with that job_id. Use list_jobs.");
  return job;
}

async function snapshotsOf(ctx: QueryCtx, userId: string, jobId: string) {
  return live(
    await ctx.db
      .query("wage_snapshots")
      .withIndex("by_user_job_from_date", (q) => q.eq("user_id", userId).eq("job_id", jobId))
      .collect(),
  );
}

const writes = { payroll_revision: PAYROLL_REVISION };

// ---------- Reads ----------

export const listJobs = internalQuery({
  args: { user_id: v.string(), include_archived: v.boolean() },
  handler: async (ctx, { user_id, include_archived }) => {
    const withPay = await jobsWithPay(ctx, user_id);
    const jobs = await jobsOf(ctx, user_id);
    const archived = include_archived ? jobs.filter((j) => j.archived_at !== undefined) : [];
    return { jobs: [...activeJobs(jobs), ...archived].map((j) => jobView(j, withPay.has(j.id))) };
  },
});

export const getPay = internalQuery({
  args: { user_id: v.string(), job_id: v.string() },
  handler: async (ctx, { user_id, job_id }) => {
    const job = await ownJob(ctx, user_id, job_id);
    return payView(job, await snapshotsOf(ctx, user_id, job.id));
  },
});

// ---------- Jobs ----------

export const addJob = internalMutation({
  args: {
    user_id: v.string(),
    name: v.string(),
    color: v.string(),
    currency: v.optional(v.string()),
    payroll_day: v.number(),
    half_tax_month: v.optional(v.union(v.literal(11), v.literal(12))),
    pay_period: v.optional(v.any()),
    settings: v.any(),
    today: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const jobs = await jobsOf(ctx, user.id);
    const active = activeJobs(jobs);
    // A retried call finds the job its first attempt added.
    const existing = active.find((j) => j.name.toLowerCase() === args.name.toLowerCase());
    if (existing !== undefined) {
      return { job: jobView(existing, (await jobsWithPay(ctx, user.id)).has(existing.id)), already_existed: true };
    }
    const currency = args.currency ?? active.find((j) => j.is_default)?.currency ?? "kr";
    const fields = checked(() => snapshotFields(args.settings as PaySettings, null, { date: args.today, currency }));
    const { sortOrder, isDefault } = placement(active);
    const { row: job } = await jobWrites.insert(ctx, user.id, {
      row: jobRow({
        id: crypto.randomUUID(),
        name: args.name,
        color: args.color,
        currency,
        isDefault,
        sortOrder,
        payrollDay: args.payroll_day,
        halfTaxMonth: args.half_tax_month,
        payPeriod: args.pay_period,
      }),
      ...writes,
    });
    // One transaction: a snapshot the server refuses leaves no job behind.
    const { row: snapshot } = await wageSnapshotWrites.insert(ctx, user.id, {
      row: snapshotRow(crypto.randomUUID(), job.id, undefined, fields),
      ...writes,
    });
    return {
      job: jobView(job as Doc<"jobs">, true),
      pay: payView(job as Doc<"jobs">, [snapshot as Doc<"wage_snapshots">]).pay,
      already_existed: false,
    };
  },
});

export const updateJob = internalMutation({
  args: {
    user_id: v.string(),
    job_id: v.string(),
    revision: v.number(),
    name: v.optional(v.string()),
    color: v.optional(v.string()),
    payroll_day: v.optional(v.number()),
    half_tax_month: v.optional(v.union(v.literal(11), v.literal(12), v.null())),
    pay_period: v.optional(v.any()),
    make_default: v.optional(v.boolean()),
    archived: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const job = await ownJob(ctx, user.id, args.job_id);
    if (job.revision !== args.revision) fail(JOB_STALE);
    const active = activeJobs(await jobsOf(ctx, user.id));
    const isArchived = job.archived_at !== undefined;

    const set: Record<string, unknown> = {};
    const clear: string[] = [];
    const change = (key: keyof Doc<"jobs">, value: unknown) => {
      const stored = job[key];
      if (value === null) {
        if (stored !== undefined) clear.push(key);
      } else if (value !== undefined && JSON.stringify(value) !== JSON.stringify(stored)) {
        set[key] = value;
      }
    };
    change("name", args.name);
    change("color", args.color);
    change("payroll_day", args.payroll_day);
    change("half_tax_month", args.half_tax_month);
    change("pay_period", args.pay_period);

    if (args.archived === true && !isArchived) {
      const refusal = archiveRefusal(job, active);
      if (refusal !== null) fail(refusal);
      Object.assign(set, { archived_at: new Date().toISOString(), is_default: false });
    } else if (args.archived === false && isArchived) {
      clear.push("archived_at");
      set.sort_order = placement(active).sortOrder;
    }

    if (args.make_default && !job.is_default) {
      if (isArchived && args.archived !== false) fail("An archived job can't be the default. Restore it first with archived: false.");
      // One live default per user: the old default gives it up first.
      const previous = active.find((j) => j.is_default);
      if (previous !== undefined) {
        const result = await jobWrites.update(ctx, user.id, {
          id: previous.id,
          expected_revision: previous.revision,
          set: { is_default: false },
          ...writes,
        });
        if (result.status !== "ok") fail("Another change to the user's jobs got there first. Call list_jobs and try again.");
      }
      set.is_default = true;
    }

    const paySetUp = (await jobsWithPay(ctx, user.id)).has(job.id);
    // Nothing to change keeps the revision the agent holds.
    if (Object.keys(set).length === 0 && clear.length === 0) return { job: jobView(job, paySetUp) };
    const result = await jobWrites.update(ctx, user.id, {
      id: job.id,
      expected_revision: job.revision,
      set,
      clear,
      ...writes,
    });
    if (result.status !== "ok") fail(JOB_STALE);
    return { job: jobView(result.row as Doc<"jobs">, paySetUp) };
  },
});

export const deleteJob = internalMutation({
  args: { user_id: v.string(), job_id: v.string(), confirmation_token: v.optional(v.string()) },
  handler: async (ctx, { user_id, ...args }) => {
    const user = await requireUser(ctx, user_id);
    const job = await ctx.db.query("jobs").withIndex("by_uuid", (q) => q.eq("id", args.job_id)).unique();
    // A deleted job is found only by a retry that holds the token, which returns the deletion.
    if (job === null || job.user_id !== user.id || (job.deleted_at !== undefined && args.confirmation_token === undefined)) {
      fail("No job with that job_id. Use list_jobs with include_archived.");
    }
    if (job.deleted_at === undefined && job.archived_at === undefined) {
      fail("Only an archived job can be deleted. Archive it with update_job first.");
    }
    let result;
    try {
      result = await deleteArchivedFor(ctx, user.id, args);
    } catch (error) {
      if (error instanceof ConvexError && (error.data as { code?: string }).code === "history_changed") {
        fail("The job's history changed since the first call. Call delete_job again without a token and confirm the new counts.");
      }
      throw error;
    }
    const counts = {
      shifts: result.user_shifts,
      recurring_shifts: result.recurring_shifts,
      payroll_adjustments: result.payroll_adjustments,
      pay_settings: result.wage_snapshots,
    };
    if (result.deleted_at_epoch === null) {
      return {
        deleted: false,
        job_name: result.job_name,
        would_delete: counts,
        confirmation_token: result.confirmation_token,
        next: "Confirm with the user, then call delete_job again with this confirmation_token.",
      };
    }
    return { deleted: true, job_name: result.job_name, deleted_rows: counts };
  },
});

// ---------- Pay ----------

export const setPay = internalMutation({
  args: {
    user_id: v.string(),
    job_id: v.string(),
    from_date: v.optional(v.string()),
    revision: v.optional(v.number()),
    settings: v.any(),
    today: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const job = await ownJob(ctx, user.id, args.job_id);
    if (job.archived_at !== undefined) fail("The job is archived. Restore it with update_job first.");
    const snapshots = await snapshotsOf(ctx, user.id, job.id);
    if (args.from_date !== undefined && !snapshots.some((s) => s.from_date === undefined)) {
      fail("Set the job's base pay first: call set_pay without from_date.");
    }
    const target = snapshots.find((s) => s.from_date === args.from_date);
    const base = target ?? (args.from_date === undefined ? null : snapshotInEffect(snapshots, args.from_date));
    const fields = checked(() =>
      snapshotFields(args.settings as PaySettings, base, { date: args.from_date ?? args.today, currency: job.currency }),
    );
    const view = (rows: Doc<"wage_snapshots">[]) => payView(job, rows);

    if (target === undefined) {
      const { row } = await wageSnapshotWrites.insert(ctx, user.id, {
        row: snapshotRow(crypto.randomUUID(), job.id, args.from_date, fields),
        ...writes,
      });
      return { changed: true, ...view([...snapshots, row as Doc<"wage_snapshots">]) };
    }
    const update = snapshotUpdate(target, fields);
    // A retried call, or one that changes nothing, needs no revision and keeps it.
    if (update === null) return { changed: false, ...view(snapshots) };
    if (args.revision === undefined) {
      fail(
        `${args.from_date === undefined ? "The base pay" : `Pay from ${args.from_date}`} is already set. ` +
          "Call get_pay and pass its revision to change it.",
      );
    }
    if (args.revision !== target.revision) fail(PAY_STALE);
    const result = await wageSnapshotWrites.update(ctx, user.id, {
      id: target.id,
      expected_revision: target.revision,
      ...update,
      ...writes,
    });
    if (result.status !== "ok") fail(PAY_STALE);
    return {
      changed: true,
      ...view(snapshots.map((s) => (s.id === target.id ? (result.row as Doc<"wage_snapshots">) : s))),
    };
  },
});

export const deletePayChange = internalMutation({
  args: { user_id: v.string(), snapshot_id: v.string(), revision: v.number() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const snapshot = await ctx.db.query("wage_snapshots").withIndex("by_uuid", (q) => q.eq("id", args.snapshot_id)).unique();
    if (snapshot === null || snapshot.user_id !== user.id || snapshot.deleted_at !== undefined) {
      fail("No pay change with that snapshot_id. Use get_pay.");
    }
    if (snapshot.from_date === undefined) fail("The base pay can't be deleted. Change it with set_pay instead.");
    if (snapshot.revision !== args.revision) fail(PAY_STALE);
    const result = await wageSnapshotWrites.remove(ctx, user.id, {
      id: snapshot.id,
      expected_revision: snapshot.revision,
      ...writes,
    });
    if (result.status !== "ok") fail(PAY_STALE);
    const job = await ownJob(ctx, user.id, snapshot.job_id);
    return { deleted_from_date: snapshot.from_date, ...payView(job, await snapshotsOf(ctx, user.id, job.id)) };
  },
});

export const payTools: McpTool[] = [
  tool(specs.listJobs, (ctx, user_id, args) => ctx.runQuery(internal.mcpPay.listJobs, { user_id, ...args })),
  tool(specs.addJob, (ctx, user_id, args) => ctx.runMutation(internal.mcpPay.addJob, { user_id, ...args })),
  tool(specs.updateJob, (ctx, user_id, args) => ctx.runMutation(internal.mcpPay.updateJob, { user_id, ...args })),
  tool(specs.deleteJob, (ctx, user_id, args) => ctx.runMutation(internal.mcpPay.deleteJob, { user_id, ...args })),
  tool(specs.listTariffsSpec, async (_ctx, _user_id, args) => listTariffs(args.search)),
  tool(specs.getTariffSpec, async (_ctx, _user_id, args) => getTariff(args.tariff_type_id)),
  tool(specs.getPay, (ctx, user_id, args) => ctx.runQuery(internal.mcpPay.getPay, { user_id, ...args })),
  tool(specs.setPay, (ctx, user_id, args) => ctx.runMutation(internal.mcpPay.setPay, { user_id, ...args })),
  tool(specs.deletePayChange, (ctx, user_id, args) => ctx.runMutation(internal.mcpPay.deletePayChange, { user_id, ...args })),
];
