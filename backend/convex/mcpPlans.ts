import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, type QueryCtx } from "./_generated/server";
import { eventWrites } from "./events";
import { checked, fail, jobForShift, jobsOf, live, requireUser } from "./lib/mcp/db";
import { computeAdjustmentWithPay } from "./lib/mcp/earnings";
import { adjustmentFields, changedEvent, type EventFields, eventFields, eventView } from "./lib/mcp/plans";
import * as specs from "./lib/mcp/plans";
import {
  firstDate,
  overlappingDates,
  previewEnd,
  recurringView,
  sameSeries,
  type Series,
  seriesDates,
  seriesUpdate,
  storedEndCondition,
} from "./lib/mcp/recurring";
import * as recurring from "./lib/mcp/recurring";
import { type McpTool, tool } from "./lib/mcp/registry";
import { addDays } from "./lib/mcp/shiftTimes";
import { PAYROLL_REVISION } from "./lib/payrollCompatibility";
import { saveScheduleTimeZone, scheduleTimeZone } from "./lib/scheduleTimeZone";
import type { LiveActivityRegularShift } from "./lib/shared/liveActivityScheduling";
import { applicableWageSnapshot, asSnapshot } from "./liveActivities";
import { adjustmentWrites } from "./payrollAdjustments";
import { recurringWrites } from "./recurringShifts";
import { updateSettingsFor } from "./userSettings";

// The MCP tools for recurring shifts, events, payroll adjustments and settings.
// Each runs for the user the OAuth token names; none of these functions is public.

type Row<T extends "recurring_shifts" | "events" | "payroll_adjustments"> = Omit<Doc<T>, "_id" | "_creationTime">;

/** The row `id` of the user's, live. */
async function own<T extends "recurring_shifts" | "events" | "payroll_adjustments">(
  ctx: QueryCtx,
  table: T,
  userId: string,
  id: string,
  hint: string,
) {
  const row = (await ctx.db
    .query(table as "events")
    .withIndex("by_uuid", (q) => q.eq("id", id))
    .unique()) as Doc<T> | null;
  if (row === null || row.user_id !== userId || row.deleted_at !== undefined) {
    fail(`Nothing found with id "${id}". ${hint}`);
  }
  return row;
}

/** The columns of `next` that differ from `prev`: what to set, and what to clear. */
function diff(prev: Record<string, unknown>, next: Record<string, unknown>, columns: string[]) {
  const set: Record<string, unknown> = {};
  const clear: string[] = [];
  for (const column of columns) {
    if (next[column] === undefined) {
      if (prev[column] !== undefined) clear.push(column);
    } else if (JSON.stringify(next[column]) !== JSON.stringify(prev[column])) {
      set[column] = next[column];
    }
  }
  return { set, clear };
}

const nothingChanged = (change: { set: Record<string, unknown>; clear: string[] }) =>
  Object.keys(change.set).length === 0 && change.clear.length === 0;

const jobName = (jobs: Doc<"jobs">[], jobId: string | undefined) => jobs.find((j) => j.id === jobId)?.name ?? null;

// ---------- Recurring shifts ----------

const asSeries = (r: Row<"recurring_shifts">): Series => ({
  selected_days: r.selected_days as Record<string, string>,
  repeat_interval_weeks: r.repeat_interval_weeks,
  end_condition: storedEndCondition(r.end_condition),
  exclusions: (r.exclusions as string[] | undefined) ?? [],
});

const recurringOf = async (ctx: QueryCtx, userId: string) =>
  live(await ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect());

const endCondition = v.union(
  v.object({ type: v.literal("months"), value: v.number() }),
  v.object({ type: v.literal("years"), value: v.number() }),
  v.object({ type: v.literal("end_date"), date: v.string() }),
);

export const createRecurringShift = internalMutation({
  args: {
    user_id: v.string(),
    selected_days: v.record(v.string(), v.string()),
    start_time: v.string(),
    end_time: v.string(),
    repeat_interval_weeks: v.number(),
    end_condition: v.union(endCondition, v.null()),
    job: v.optional(v.string()),
  },
  handler: async (ctx, { user_id, job: jobRef, ...args }) => {
    const user = await requireUser(ctx, user_id);
    const job = await jobForShift(ctx, user.id, jobRef);
    const jobs = await jobsOf(ctx, user.id);
    const series = { ...args, exclusions: [] };
    const others = await recurringOf(ctx, user.id);
    const existing = others.find((r) => r.job_id === job.id && sameSeries({ ...r, ...asSeries(r) }, series));
    if (existing !== undefined) {
      return { recurring_shift: recurringView(existing, jobName(jobs, existing.job_id)), already_existed: true, skipped_dates: [] };
    }

    const from = firstDate(series);
    const to = previewEnd(series);
    const oneOffs = live(
      await ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) =>
          q.eq("user_id", user.id).gte("shift_date", addDays(from, -1)).lte("shift_date", addDays(to, 1)),
        )
        .collect(),
    ).map((s) => ({ date: s.shift_date, start: s.start_time, end: s.end_time }));
    const occurrences = others.flatMap((r) =>
      seriesDates(asSeries(r), addDays(from, -1), addDays(to, 1)).map((date) => ({ date, start: r.start_time, end: r.end_time })),
    );
    const skipped = overlappingDates(seriesDates(series, from, to), args.start_time, args.end_time, [...oneOffs, ...occurrences]);

    const { row } = await recurringWrites.insert(ctx, user.id, {
      row: {
        id: crypto.randomUUID(),
        job_id: job.id,
        start_time: args.start_time,
        end_time: args.end_time,
        repeat_interval_weeks: args.repeat_interval_weeks,
        selected_days: args.selected_days,
        ...(args.end_condition === null ? {} : { end_condition: args.end_condition }),
        exclusions: skipped,
      },
      payroll_revision: PAYROLL_REVISION,
    });
    const inserted = row as Row<"recurring_shifts">;
    return {
      recurring_shift: recurringView(inserted, jobName(jobs, inserted.job_id)),
      already_existed: false,
      ...(skipped.length > 0 ? { skipped_dates: skipped } : {}),
    };
  },
});

export const updateRecurringShift = internalMutation({
  args: {
    user_id: v.string(),
    id: v.string(),
    selected_days: v.optional(v.record(v.string(), v.string())),
    start: v.optional(v.string()),
    end: v.optional(v.string()),
    repeat_interval_weeks: v.optional(v.number()),
    end_condition: v.optional(v.object({ value: v.union(endCondition, v.null()) })),
    job: v.optional(v.string()),
    unskip_dates: v.optional(v.array(v.string())),
  },
  handler: async (ctx, { user_id, id, job: jobRef, ...change }) => {
    const user = await requireUser(ctx, user_id);
    const prev = await own(ctx, "recurring_shifts", user.id, id, "Use a recurring_shift id from get_overview.");
    const jobs = await jobsOf(ctx, user.id);
    const update = checked(() => seriesUpdate({ ...asSeries(prev), start_time: prev.start_time, end_time: prev.end_time }, change));
    if (jobRef !== undefined) {
      const targetJob = await jobForShift(ctx, user.id, jobRef);
      if (targetJob.id !== prev.job_id) update.set.job_id = targetJob.id;
    }
    if (nothingChanged(update)) return { recurring_shift: recurringView(prev, jobName(jobs, prev.job_id)) };
    const result = await recurringWrites.update(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      ...update,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail("The recurring shift changed during the update. Try again.");
    const row = result.row as Row<"recurring_shifts">;
    return { recurring_shift: recurringView(row, jobName(jobs, row.job_id)) };
  },
});

export const deleteRecurringShift = internalMutation({
  args: { user_id: v.string(), id: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await own(ctx, "recurring_shifts", user.id, args.id, "Use a recurring_shift id from get_overview.");
    const result = await recurringWrites.remove(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail("The recurring shift changed during deletion. Try again.");
    const jobs = await jobsOf(ctx, user.id);
    const row = result.row as Row<"recurring_shifts">;
    return { deleted: recurringView(row, jobName(jobs, row.job_id)) };
  },
});

// ---------- Events ----------

const EVENT_COLUMNS = [
  "start_date",
  "end_date",
  "is_all_day",
  "start_time",
  "end_time",
  "note",
  "notification_minutes_array",
  "notification_anchor_time",
];

const eventsOf = async (ctx: QueryCtx, userId: string) =>
  live(await ctx.db.query("events").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect());

const eventFieldsValidator = {
  start_date: v.string(),
  end_date: v.string(),
  is_all_day: v.boolean(),
  start_time: v.optional(v.string()),
  end_time: v.optional(v.string()),
  note: v.string(),
  notification_minutes_array: v.optional(v.array(v.number())),
  notification_anchor_time: v.optional(v.string()),
};

export const createEvent = internalMutation({
  args: { user_id: v.string(), ...eventFieldsValidator },
  handler: async (ctx, { user_id, ...fields }) => {
    const user = await requireUser(ctx, user_id);
    const key = ["start_date", "end_date", "is_all_day", "start_time", "end_time", "note"] as const;
    const existing = (await eventsOf(ctx, user.id)).find((e) => key.every((k) => e[k] === fields[k]));
    if (existing !== undefined) return { event: eventView(existing), already_existed: true };
    const { row } = await eventWrites.insert(ctx, user.id, { row: { id: crypto.randomUUID(), ...fields }, payroll_revision: PAYROLL_REVISION });
    return { event: eventView(row as Row<"events">), already_existed: false };
  },
});

export const updateEvent = internalMutation({
  args: {
    user_id: v.string(),
    id: v.string(),
    change: v.object({
      note: v.optional(v.string()),
      date: v.optional(v.string()),
      end_date: v.optional(v.string()),
      start: v.optional(v.string()),
      end: v.optional(v.string()),
      reminder_minutes: v.optional(v.array(v.number())),
      reminder_days_before: v.optional(v.array(v.number())),
      reminder_time: v.optional(v.string()),
      all_day: v.optional(v.boolean()),
    }),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await own(ctx, "events", user.id, args.id, "Use an event id from get_schedule.");
    const next: EventFields = checked(() => eventFields(changedEvent(prev, args.change)));
    const change = diff(prev, next, EVENT_COLUMNS);
    if (nothingChanged(change)) return { event: eventView(prev) };
    const result = await eventWrites.update(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      ...change,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail("The event changed during the update. Try again.");
    return { event: eventView(result.row as Row<"events">) };
  },
});

export const deleteEvent = internalMutation({
  args: { user_id: v.string(), id: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await own(ctx, "events", user.id, args.id, "Use an event id from get_schedule.");
    const result = await eventWrites.remove(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail("The event changed during deletion. Try again.");
    return { deleted: eventView(result.row as Row<"events">) };
  },
});

// ---------- Payroll adjustments ----------

const ADJUSTMENT_COLUMNS = [
  "job_id",
  "amount",
  "currency",
  "category",
  "tax_treatment",
  "description",
  "note",
  "earned_from_date",
  "earned_to_date",
  "payout_date",
];

const adjustmentsOf = async (ctx: QueryCtx, userId: string) =>
  live(await ctx.db.query("payroll_adjustments").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect());

async function adjustmentOut(ctx: QueryCtx, userId: string, a: Row<"payroll_adjustments">, jobs: Doc<"jobs">[]) {
  const [rawSnapshots, settings] = await Promise.all([
    ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect(),
    ctx.db.query("user_settings").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).unique(),
  ]);
  const snapshots = live(rawSnapshots).map(asSnapshot);
  const { raw: _raw, ...computed } = computeAdjustmentWithPay(
    a,
    jobs,
    (jobId, date) => applicableWageSnapshot({ user_id: userId, job_id: jobId, shift_date: date } as LiveActivityRegularShift, snapshots),
    settings?.half_tax_month,
  );
  return computed;
}

async function payFor(ctx: QueryCtx, userId: string, job: Doc<"jobs">, payoutDate: string) {
  const snapshots = live(
    await ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect(),
  ).map(asSnapshot);
  const shift = { user_id: userId, job_id: job.id, shift_date: payoutDate } as LiveActivityRegularShift;
  return { id: job.id, currency: job.currency, taxEnabled: applicableWageSnapshot(shift, snapshots)?.tax_enabled === true };
}

export const createPayrollAdjustment = internalMutation({
  args: {
    user_id: v.string(),
    job: v.optional(v.string()),
    amount: v.number(),
    description: v.string(),
    note: v.optional(v.string()),
    category: v.string(),
    tax_treatment: v.optional(v.string()),
    earned_from: v.optional(v.string()),
    earned_to: v.optional(v.string()),
    payout_date: v.string(),
  },
  handler: async (ctx, { user_id, job: jobRef, ...draft }) => {
    const user = await requireUser(ctx, user_id);
    const job = await jobForShift(ctx, user.id, jobRef);
    const pay = await payFor(ctx, user.id, job, draft.payout_date);
    const row = checked(() => adjustmentFields(draft, pay));
    const jobs = await jobsOf(ctx, user.id);
    const existing = (await adjustmentsOf(ctx, user.id)).find(
      (a) => a.job_id === row.job_id && a.payout_date === row.payout_date && a.amount === row.amount && a.description === row.description,
    );
    if (existing !== undefined) {
      return { adjustment: await adjustmentOut(ctx, user.id, existing, jobs), already_existed: true };
    }
    const result = await adjustmentWrites.insert(ctx, user.id, {
      row: { id: crypto.randomUUID(), ...row } as Parameters<typeof adjustmentWrites.insert>[2]["row"],
      payroll_revision: PAYROLL_REVISION,
    });
    return { adjustment: await adjustmentOut(ctx, user.id, result.row as Row<"payroll_adjustments">, jobs), already_existed: false };
  },
});

export const updatePayrollAdjustment = internalMutation({
  args: {
    user_id: v.string(),
    id: v.string(),
    change: v.object({
      job: v.optional(v.string()),
      amount: v.optional(v.number()),
      description: v.optional(v.string()),
      category: v.optional(v.string()),
      tax_treatment: v.optional(v.string()),
      payout_date: v.optional(v.string()),
      earned_from: v.optional(v.string()),
      earned_to: v.optional(v.string()),
      note: v.optional(v.string()),
    }),
  },
  handler: async (ctx, { user_id, id, change }) => {
    const user = await requireUser(ctx, user_id);
    const prev = await own(ctx, "payroll_adjustments", user.id, id, "Use an adjustment id from get_earnings.");
    const jobs = await jobsOf(ctx, user.id);
    const job =
      change.job !== undefined
        ? await jobForShift(ctx, user.id, change.job)
        : prev.job_id !== undefined
          ? jobs.find((j) => j.id === prev.job_id)
          : undefined;
    if (job === undefined) fail("This adjustment has no active job. Pass job (ID or name).");
    const earned = (given: string | undefined, stored: string | undefined) => (given === "" ? undefined : (given ?? stored));
    const draft = {
      amount: change.amount ?? prev.amount,
      description: change.description ?? prev.description,
      note: change.note ?? prev.note,
      category: change.category ?? prev.category,
      tax_treatment: change.tax_treatment ?? prev.tax_treatment,
      earned_from: earned(change.earned_from, prev.earned_from_date),
      earned_to: earned(change.earned_to, prev.earned_to_date),
      payout_date: change.payout_date ?? prev.payout_date,
    };
    const pay = await payFor(ctx, user.id, job, draft.payout_date);
    const next = checked(() => adjustmentFields(draft, pay));
    const update = diff(prev, next, ADJUSTMENT_COLUMNS);
    if (nothingChanged(update)) return { adjustment: await adjustmentOut(ctx, user.id, prev, jobs) };
    const result = await adjustmentWrites.update(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      ...update,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail("The payroll adjustment changed during the update. Try again.");
    return { adjustment: await adjustmentOut(ctx, user.id, result.row as Row<"payroll_adjustments">, jobs) };
  },
});

export const deletePayrollAdjustment = internalMutation({
  args: { user_id: v.string(), id: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await own(ctx, "payroll_adjustments", user.id, args.id, "Use an adjustment id from get_earnings.");
    const result = await adjustmentWrites.remove(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail("The payroll adjustment changed during deletion. Try again.");
    const jobs = await jobsOf(ctx, user.id);
    return { deleted: await adjustmentOut(ctx, user.id, result.row as Row<"payroll_adjustments">, jobs) };
  },
});

// ---------- Settings ----------

const literals = <T extends string>(values: readonly T[]) => v.union(...values.map((value) => v.literal(value)));

export const updateSettings = internalMutation({
  args: {
    user_id: v.string(),
    user_settings: v.object({
      theme: v.optional(literals(specs.THEMES)),
      calendar_content_color_style: v.optional(literals(specs.CALENDAR_COLORS)),
      show_dashboard_clock_buttons: v.optional(v.boolean()),
      default_startup_tab: v.optional(literals(specs.STARTUP_TABS)),
    }),
    schedule_time_zone: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    if (Object.keys(args.user_settings).length > 0) {
      const prev = await ctx.db.query("user_settings").withIndex("by_user_revision", (q) => q.eq("user_id", user.id)).unique();
      if (prev === null) fail("The user has no settings yet. They need to open the Tidex app once first.");
      const { set } = diff(prev, args.user_settings, Object.keys(args.user_settings));
      if (Object.keys(set).length > 0) await updateSettingsFor(ctx, user.id, { expected_revision: prev.revision, set });
    }
    if (args.schedule_time_zone !== undefined && args.schedule_time_zone !== (await scheduleTimeZone(ctx, user.id))) {
      await saveScheduleTimeZone(ctx, user.id, args.schedule_time_zone, false);
    }
    const updated = await ctx.db.query("user_settings").withIndex("by_user_revision", (q) => q.eq("user_id", user.id)).unique();
    return {
      time_zone: await scheduleTimeZone(ctx, user.id),
      settings: {
        theme: updated?.theme ?? null,
        calendar_color_style: updated?.calendar_content_color_style ?? null,
        show_clock_buttons: updated?.show_dashboard_clock_buttons ?? null,
        startup_tab: updated?.default_startup_tab ?? null,
      },
    };
  },
});

export const planTools: McpTool[] = [
  tool(recurring.saveRecurringShift, (ctx, user_id, args) =>
    args.mode === "create"
      ? ctx.runMutation(internal.mcpPlans.createRecurringShift, {
          user_id,
          selected_days: args.selected_days,
          start_time: args.start_time,
          end_time: args.end_time,
          repeat_interval_weeks: args.repeat_interval_weeks,
          end_condition: args.end_condition,
          job: args.job,
        })
      : ctx.runMutation(internal.mcpPlans.updateRecurringShift, {
          user_id,
          id: args.id,
          selected_days: args.selected_days,
          start: args.start,
          end: args.end,
          repeat_interval_weeks: args.repeat_interval_weeks,
          end_condition: args.end_condition,
          job: args.job,
          unskip_dates: args.unskip_dates,
        }),
  ),
  tool(recurring.deleteRecurringShift, (ctx, user_id, args) =>
    ctx.runMutation(internal.mcpPlans.deleteRecurringShift, { user_id, ...args }),
  ),
  tool(specs.saveEvent, (ctx, user_id, args) =>
    args.mode === "create"
      ? ctx.runMutation(internal.mcpPlans.createEvent, { user_id, ...args.fields })
      : ctx.runMutation(internal.mcpPlans.updateEvent, { user_id, id: args.id, change: args.change }),
  ),
  tool(specs.deleteEvent, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.deleteEvent, { user_id, ...args })),
  tool(specs.savePayrollAdjustment, (ctx, user_id, args) =>
    args.mode === "create"
      ? ctx.runMutation(internal.mcpPlans.createPayrollAdjustment, {
          user_id,
          job: args.job,
          amount: args.amount,
          description: args.description,
          note: args.note,
          category: args.category,
          tax_treatment: args.tax_treatment,
          earned_from: args.earned_from,
          earned_to: args.earned_to,
          payout_date: args.payout_date,
        })
      : ctx.runMutation(internal.mcpPlans.updatePayrollAdjustment, { user_id, id: args.id, change: args.change }),
  ),
  tool(specs.deletePayrollAdjustment, (ctx, user_id, args) =>
    ctx.runMutation(internal.mcpPlans.deletePayrollAdjustment, { user_id, ...args }),
  ),
  tool(specs.updateSettings, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.updateSettings, { user_id, ...args })),
];
