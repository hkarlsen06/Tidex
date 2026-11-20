import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import { adjustmentWrites } from "./payrollAdjustments";
import { eventWrites } from "./events";
import { checked, fail, jobForShift, jobsOf, live, requireUser } from "./lib/mcp/db";
import { adjustmentFields, changedEvent, type EventFields, eventFields, reminderSettings } from "./lib/mcp/plans";
import * as specs from "./lib/mcp/plans";
import {
  firstDate,
  lastDate,
  overlappingDates,
  planOccurrence,
  previewEnd,
  sameSeries,
  type Series,
  seriesDates,
  seriesUpdate,
  stoppedEnd,
  storedEndCondition,
  WEEKDAYS,
} from "./lib/mcp/recurring";
import * as recurring from "./lib/mcp/recurring";
import { type McpTool, tool } from "./lib/mcp/registry";
import { addDays, clockTime, endsNextDay } from "./lib/mcp/shiftTimes";
import { PAYROLL_REVISION } from "./lib/payrollCompatibility";
import { saveScheduleTimeZone, scheduleTimeZone } from "./lib/scheduleTimeZone";
import type { LiveActivityRegularShift } from "./lib/shared/liveActivityScheduling";
import { applicableWageSnapshot, asSnapshot } from "./liveActivities";
import { oneOff } from "./mcpShifts";
import { upsertNotificationPreferencesFor } from "./notificationPreferences";
import { recurringWrites } from "./recurringShifts";
import { shiftWrites } from "./userShifts";
import { updateSettingsFor } from "./userSettings";

// The MCP tools for recurring shifts, events, payroll adjustments and settings. Each runs
// for the user the OAuth token names; mcp.ts checks the token, the scope and the
// arguments first. lib/mcp/recurring.ts and lib/mcp/plans.ts build the rows. None of these functions is public.

type Row<T extends "recurring_shifts" | "events" | "payroll_adjustments"> = Omit<Doc<T>, "_id" | "_creationTime">;

const STALE = (listTool: string) => `It changed since you listed it. Call ${listTool} again and use the new revision.`;

/** The row `id` of the user's, live and at `revision`. */
async function own<T extends "recurring_shifts" | "events" | "payroll_adjustments">(
  ctx: QueryCtx,
  table: T,
  userId: string,
  id: string,
  revision: number,
  listTool: string,
) {
  const row = (await ctx.db
    .query(table as "events")
    .withIndex("by_uuid", (q) => q.eq("id", id))
    .unique()) as Doc<T> | null;
  if (row === null || row.user_id !== userId || row.deleted_at !== undefined) fail(`Nothing with that id. Use an id from ${listTool}.`);
  if (row.revision !== revision) fail(STALE(listTool));
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

const notesOf = (r: Row<"recurring_shifts">) => (r.date_specific_notes as Record<string, string> | undefined) ?? {};

function recurringOut(r: Row<"recurring_shifts">, jobs: Doc<"jobs">[]) {
  const series = asSeries(r);
  return {
    recurring_shift_id: r.id,
    revision: r.revision,
    job_id: r.job_id,
    job_name: jobName(jobs, r.job_id),
    start: clockTime(r.start_time),
    end: clockTime(r.end_time),
    ends_next_day: endsNextDay(r.start_time, r.end_time),
    every_weeks: r.repeat_interval_weeks + 1,
    days: Object.entries(series.selected_days)
      .sort(([, a], [, b]) => a.localeCompare(b))
      .map(([weekday, first_date]) => ({ weekday: WEEKDAYS[Number(weekday)], first_date })),
    ends: series.end_condition ?? { type: "never" },
    last_date: lastDate(series),
    skipped_dates: [...series.exclusions].sort(),
    notes: notesOf(r),
  };
}

const recurringOf = async (ctx: QueryCtx, userId: string) =>
  live(await ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect());

export const listRecurringShifts = internalQuery({
  args: { user_id: v.string() },
  handler: async (ctx, { user_id }) => {
    const jobs = await jobsOf(ctx, user_id);
    return {
      time_zone: await scheduleTimeZone(ctx, user_id),
      recurring_shifts: (await recurringOf(ctx, user_id)).map((r) => recurringOut(r, jobs)),
    };
  },
});

const endCondition = v.union(
  v.object({ type: v.literal("months"), value: v.number() }),
  v.object({ type: v.literal("years"), value: v.number() }),
  v.object({ type: v.literal("end_date"), date: v.string() }),
);

export const addRecurringShift = internalMutation({
  args: {
    user_id: v.string(),
    selected_days: v.record(v.string(), v.string()),
    start_time: v.string(),
    end_time: v.string(),
    repeat_interval_weeks: v.number(),
    end_condition: v.union(endCondition, v.null()),
    job_id: v.optional(v.string()),
  },
  handler: async (ctx, { user_id, job_id, ...args }) => {
    const user = await requireUser(ctx, user_id);
    const job = await jobForShift(ctx, user.id, job_id);
    const jobs = await jobsOf(ctx, user.id);
    const series = { ...args, exclusions: [] };
    const others = await recurringOf(ctx, user.id);
    // A retried call finds the series its first attempt added.
    const existing = others.find((r) => r.job_id === job.id && sameSeries({ ...r, ...asSeries(r) }, series));
    if (existing !== undefined) return { recurring_shift: recurringOut(existing, jobs), already_existed: true, skipped_dates: [] };

    // AddShiftViewModel+RecurringShift: dates that overlap a shift the user already has are skipped.
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
    return { recurring_shift: recurringOut(row as Row<"recurring_shifts">, jobs), already_existed: false, skipped_dates: skipped };
  },
});

async function writeSeries(
  ctx: Parameters<typeof recurringWrites.update>[0],
  userId: string,
  prev: Row<"recurring_shifts">,
  change: { set: Record<string, unknown>; clear: string[] },
) {
  const jobs = await jobsOf(ctx, userId);
  // Nothing to change keeps the revision the agent holds.
  if (nothingChanged(change)) return recurringOut(prev, jobs);
  const result = await recurringWrites.update(ctx, userId, {
    id: prev.id,
    expected_revision: prev.revision,
    ...change,
    payroll_revision: PAYROLL_REVISION,
  });
  if (result.status !== "ok") fail(STALE("list_recurring_shifts"));
  return recurringOut(result.row as Row<"recurring_shifts">, jobs);
}

const ownSeries = (ctx: QueryCtx, userId: string, id: string, revision: number) =>
  own(ctx, "recurring_shifts", userId, id, revision, "list_recurring_shifts");

export const updateRecurringShift = internalMutation({
  args: {
    user_id: v.string(),
    recurring_shift_id: v.string(),
    revision: v.number(),
    selected_days: v.optional(v.record(v.string(), v.string())),
    start: v.optional(v.string()),
    end: v.optional(v.string()),
    repeat_interval_weeks: v.optional(v.number()),
    end_condition: v.optional(v.object({ value: v.union(endCondition, v.null()) })),
    job_id: v.optional(v.string()),
    unskip_dates: v.optional(v.array(v.string())),
  },
  handler: async (ctx, { user_id, recurring_shift_id, revision, job_id, ...change }) => {
    const user = await requireUser(ctx, user_id);
    const prev = await ownSeries(ctx, user.id, recurring_shift_id, revision);
    const update = checked(() => seriesUpdate({ ...asSeries(prev), start_time: prev.start_time, end_time: prev.end_time }, change));
    if (job_id !== undefined && job_id !== prev.job_id) update.set.job_id = (await jobForShift(ctx, user.id, job_id)).id;
    return { recurring_shift: await writeSeries(ctx, user.id, prev, update) };
  },
});

export const stopRecurringShift = internalMutation({
  args: { user_id: v.string(), recurring_shift_id: v.string(), revision: v.number(), last_date: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await ownSeries(ctx, user.id, args.recurring_shift_id, args.revision);
    const end = checked(() => stoppedEnd(asSeries(prev), args.last_date));
    return { recurring_shift: await writeSeries(ctx, user.id, prev, { set: { end_condition: end }, clear: [] }) };
  },
});

export const deleteRecurringShift = internalMutation({
  args: { user_id: v.string(), recurring_shift_id: v.string(), revision: v.number() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await ownSeries(ctx, user.id, args.recurring_shift_id, args.revision);
    const result = await recurringWrites.remove(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail(STALE("list_recurring_shifts"));
    return { deleted: recurringOut(result.row as Row<"recurring_shifts">, await jobsOf(ctx, user.id)) };
  },
});

export const changeRecurringOccurrence = internalMutation({
  args: {
    user_id: v.string(),
    recurring_shift_id: v.string(),
    revision: v.number(),
    date: v.string(),
    change: v.union(
      v.object({ kind: v.literal("skip") }),
      v.object({ kind: v.literal("note"), note: v.string() }),
      v.object({
        kind: v.literal("change"),
        date: v.optional(v.string()),
        start: v.optional(v.string()),
        end: v.optional(v.string()),
        note: v.optional(v.string()),
      }),
    ),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await ownSeries(ctx, user.id, args.recurring_shift_id, args.revision);
    const series = asSeries(prev);
    if (!seriesDates(series, args.date, args.date).includes(args.date)) {
      fail(`${args.date} is not a date of this series; it may be skipped or changed already. list_shifts shows its dates.`);
    }
    const plan = checked(() =>
      planOccurrence(
        { start_time: prev.start_time, end_time: prev.end_time, exclusions: series.exclusions, date_specific_notes: notesOf(prev) },
        args.date,
        args.change,
      ),
    );
    // The app adds the one-off shift to the series' job, which needs pay set up.
    const job = plan.shift === undefined ? null : await jobForShift(ctx, user.id, prev.job_id);
    const next = {
      exclusions: plan.exclusions ?? prev.exclusions,
      date_specific_notes: plan.date_specific_notes === undefined ? prev.date_specific_notes : (plan.date_specific_notes ?? undefined),
    };
    const recurring_shift = await writeSeries(ctx, user.id, prev, diff(prev, next, ["exclusions", "date_specific_notes"]));
    if (plan.shift === undefined || job === null) return { recurring_shift };
    const { row } = await shiftWrites.insert(ctx, user.id, {
      row: { id: crypto.randomUUID(), job_id: job.id, ...plan.shift },
      payroll_revision: PAYROLL_REVISION,
    });
    return { recurring_shift, shift: oneOff(row as Parameters<typeof oneOff>[0], await jobsOf(ctx, user.id)) };
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

function eventOut(e: Row<"events">) {
  const reminders = e.notification_minutes_array ?? [];
  return {
    event_id: e.id,
    revision: e.revision,
    date: e.start_date,
    end_date: e.end_date,
    all_day: e.is_all_day,
    note: e.note,
    ...(e.is_all_day
      ? { reminder_days_before: reminders.map((m) => m / (24 * 60)), reminder_time: e.notification_anchor_time ?? null }
      : { start: e.start_time ?? null, end: e.end_time ?? null, reminder_minutes: reminders }),
  };
}

const eventsOf = async (ctx: QueryCtx, userId: string) =>
  live(await ctx.db.query("events").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect());

export const listEvents = internalQuery({
  args: { user_id: v.string(), from: v.string(), to: v.string() },
  handler: async (ctx, { user_id, from, to }) => ({
    time_zone: await scheduleTimeZone(ctx, user_id),
    events: (await eventsOf(ctx, user_id))
      .filter((e) => e.start_date <= to && e.end_date >= from)
      .sort((a, b) => a.start_date.localeCompare(b.start_date) || (a.start_time ?? "").localeCompare(b.start_time ?? ""))
      .map(eventOut),
  }),
});

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

export const addEvent = internalMutation({
  args: { user_id: v.string(), ...eventFieldsValidator },
  handler: async (ctx, { user_id, ...fields }) => {
    const user = await requireUser(ctx, user_id);
    // A retried call finds the event its first attempt added.
    const key = ["start_date", "end_date", "is_all_day", "start_time", "end_time", "note"] as const;
    const existing = (await eventsOf(ctx, user.id)).find((e) => key.every((k) => e[k] === fields[k]));
    if (existing !== undefined) return { event: eventOut(existing), already_existed: true };
    const { row } = await eventWrites.insert(ctx, user.id, { row: { id: crypto.randomUUID(), ...fields }, payroll_revision: PAYROLL_REVISION });
    return { event: eventOut(row as Row<"events">), already_existed: false };
  },
});

export const updateEvent = internalMutation({
  args: {
    user_id: v.string(),
    event_id: v.string(),
    revision: v.number(),
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
    const prev = await own(ctx, "events", user.id, args.event_id, args.revision, "list_events");
    const next: EventFields = checked(() => eventFields(changedEvent(prev, args.change)));
    const change = diff(prev, next, EVENT_COLUMNS);
    if (nothingChanged(change)) return { event: eventOut(prev) };
    const result = await eventWrites.update(ctx, user.id, { id: prev.id, expected_revision: prev.revision, ...change, payroll_revision: PAYROLL_REVISION });
    if (result.status !== "ok") fail(STALE("list_events"));
    return { event: eventOut(result.row as Row<"events">) };
  },
});

export const deleteEvent = internalMutation({
  args: { user_id: v.string(), event_id: v.string(), revision: v.number() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await own(ctx, "events", user.id, args.event_id, args.revision, "list_events");
    const result = await eventWrites.remove(ctx, user.id, { id: prev.id, expected_revision: prev.revision, payroll_revision: PAYROLL_REVISION });
    if (result.status !== "ok") fail(STALE("list_events"));
    return { deleted: eventOut(result.row as Row<"events">) };
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

function adjustmentOut(a: Row<"payroll_adjustments">, jobs: Doc<"jobs">[]) {
  return {
    adjustment_id: a.id,
    revision: a.revision,
    job_id: a.job_id ?? null,
    job_name: jobName(jobs, a.job_id),
    amount: a.amount,
    currency: a.currency,
    category: a.category,
    tax_treatment: a.tax_treatment,
    description: a.description,
    note: a.note ?? null,
    earned_from: a.earned_from_date ?? null,
    earned_to: a.earned_to_date ?? null,
    payout_date: a.payout_date,
  };
}

const adjustmentsOf = async (ctx: QueryCtx, userId: string) =>
  live(await ctx.db.query("payroll_adjustments").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect());

/** The job's currency, and whether the pay that applies on `payoutDate` has tax. */
async function payFor(ctx: QueryCtx, userId: string, job: Doc<"jobs">, payoutDate: string) {
  const snapshots = live(
    await ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect(),
  ).map(asSnapshot);
  const shift = { user_id: userId, job_id: job.id, shift_date: payoutDate } as LiveActivityRegularShift;
  return { id: job.id, currency: job.currency, taxEnabled: applicableWageSnapshot(shift, snapshots)?.tax_enabled === true };
}

export const listPayrollAdjustments = internalQuery({
  args: { user_id: v.string(), from: v.string(), to: v.string() },
  handler: async (ctx, { user_id, from, to }) => {
    const jobs = await jobsOf(ctx, user_id);
    return {
      adjustments: (await adjustmentsOf(ctx, user_id))
        .filter((a) => a.payout_date >= from && a.payout_date <= to)
        .sort((a, b) => a.payout_date.localeCompare(b.payout_date))
        .map((a) => adjustmentOut(a, jobs)),
    };
  },
});

export const addPayrollAdjustment = internalMutation({
  args: {
    user_id: v.string(),
    job_id: v.optional(v.string()),
    amount: v.number(),
    description: v.string(),
    note: v.optional(v.string()),
    category: v.string(),
    tax_treatment: v.optional(v.string()),
    earned_from: v.optional(v.string()),
    earned_to: v.optional(v.string()),
    payout_date: v.string(),
  },
  handler: async (ctx, { user_id, job_id, ...draft }) => {
    const user = await requireUser(ctx, user_id);
    const job = await jobForShift(ctx, user.id, job_id);
    const pay = await payFor(ctx, user.id, job, draft.payout_date);
    const row = checked(() => adjustmentFields(draft, pay));
    const jobs = await jobsOf(ctx, user.id);
    // A retried call finds the adjustment its first attempt added.
    const existing = (await adjustmentsOf(ctx, user.id)).find(
      (a) => a.job_id === row.job_id && a.payout_date === row.payout_date && a.amount === row.amount && a.description === row.description,
    );
    if (existing !== undefined) return { adjustment: adjustmentOut(existing, jobs), already_existed: true };
    const result = await adjustmentWrites.insert(ctx, user.id, {
      row: { id: crypto.randomUUID(), ...row } as Parameters<typeof adjustmentWrites.insert>[2]["row"],
      payroll_revision: PAYROLL_REVISION,
    });
    return { adjustment: adjustmentOut(result.row as Row<"payroll_adjustments">, jobs), already_existed: false };
  },
});

export const updatePayrollAdjustment = internalMutation({
  args: {
    user_id: v.string(),
    adjustment_id: v.string(),
    revision: v.number(),
    change: v.object({
      job_id: v.optional(v.string()),
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
  handler: async (ctx, { user_id, adjustment_id, revision, change }) => {
    const user = await requireUser(ctx, user_id);
    const prev = await own(ctx, "payroll_adjustments", user.id, adjustment_id, revision, "list_payroll_adjustments");
    const jobs = await jobsOf(ctx, user.id);
    const jobId = change.job_id ?? prev.job_id;
    if (jobId === undefined) fail("This adjustment has no job. Give job_id.");
    const job = jobId === prev.job_id ? jobs.find((j) => j.id === jobId) : await jobForShift(ctx, user.id, jobId);
    if (job === undefined) fail("The adjustment's job is gone. Give a job_id from list_jobs.");
    // "" removes an earned date.
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
    if (nothingChanged(update)) return { adjustment: adjustmentOut(prev, jobs) };
    const result = await adjustmentWrites.update(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      ...update,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail(STALE("list_payroll_adjustments"));
    return { adjustment: adjustmentOut(result.row as Row<"payroll_adjustments">, jobs) };
  },
});

export const deletePayrollAdjustment = internalMutation({
  args: { user_id: v.string(), adjustment_id: v.string(), revision: v.number() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await own(ctx, "payroll_adjustments", user.id, args.adjustment_id, args.revision, "list_payroll_adjustments");
    const result = await adjustmentWrites.remove(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail(STALE("list_payroll_adjustments"));
    return { deleted: adjustmentOut(result.row as Row<"payroll_adjustments">, await jobsOf(ctx, user.id)) };
  },
});

// ---------- Settings ----------

const settingsOf = (ctx: QueryCtx, userId: string) =>
  ctx.db.query("user_settings").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).unique();

/** The stored preferences, or the defaults notificationPreferences.upsert gives a first write. */
async function preferencesOf(ctx: QueryCtx, userId: string) {
  const row = await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .unique();
  return {
    shared_shifts_enabled: row?.shared_shifts_enabled ?? true,
    shift_reminders_enabled: row?.shift_reminders_enabled ?? true,
    shift_reminder_minutes_array: row?.shift_reminder_minutes_array ?? (row === null ? [300] : []),
  };
}

async function settingsOut(ctx: QueryCtx, userId: string) {
  const settings = await settingsOf(ctx, userId);
  const prefs = await preferencesOf(ctx, userId);
  return {
    theme: settings?.theme ?? null,
    calendar_content_color_style: settings?.calendar_content_color_style ?? null,
    show_dashboard_clock_buttons: settings?.show_dashboard_clock_buttons ?? null,
    default_startup_tab: settings?.default_startup_tab ?? null,
    schedule_time_zone: await scheduleTimeZone(ctx, userId),
    // NotificationSettingsViewModel shows reminders as off while there is no reminder time.
    shift_reminders_enabled: prefs.shift_reminders_enabled && prefs.shift_reminder_minutes_array.length > 0,
    shift_reminder_minutes: [...prefs.shift_reminder_minutes_array].sort((a, b) => b - a),
    shared_shifts_enabled: prefs.shared_shifts_enabled,
  };
}

export const getSettings = internalQuery({
  args: { user_id: v.string() },
  handler: async (ctx, { user_id }) => ({ settings: await settingsOut(ctx, user_id) }),
});

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
    notification_preferences: v.object({
      shift_reminders_enabled: v.optional(v.boolean()),
      shift_reminder_minutes_array: v.optional(v.array(v.number())),
      shared_shifts_enabled: v.optional(v.boolean()),
    }),
    schedule_time_zone: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    if (Object.keys(args.user_settings).length > 0) {
      const prev = await settingsOf(ctx, user.id);
      if (prev === null) fail("The user has no settings yet. They need to open the Tidex app once first.");
      const { set } = diff(prev, args.user_settings, Object.keys(args.user_settings));
      if (Object.keys(set).length > 0) await updateSettingsFor(ctx, user.id, { expected_revision: prev.revision, set });
    }
    if (Object.keys(args.notification_preferences).length > 0) {
      const prev = await preferencesOf(ctx, user.id);
      const next = {
        shared_shifts_enabled: args.notification_preferences.shared_shifts_enabled ?? prev.shared_shifts_enabled,
        ...checked(() => reminderSettings(prev, args.notification_preferences)),
      };
      if (JSON.stringify(next) !== JSON.stringify(prev)) await upsertNotificationPreferencesFor(ctx, user.id, next);
    }
    if (args.schedule_time_zone !== undefined && args.schedule_time_zone !== (await scheduleTimeZone(ctx, user.id))) {
      await saveScheduleTimeZone(ctx, user.id, args.schedule_time_zone, false);
    }
    return { settings: await settingsOut(ctx, user.id) };
  },
});

export const planTools: McpTool[] = [
  tool(recurring.listRecurringShifts, (ctx, user_id) => ctx.runQuery(internal.mcpPlans.listRecurringShifts, { user_id })),
  tool(recurring.addRecurringShift, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.addRecurringShift, { user_id, ...args })),
  tool(recurring.updateRecurringShift, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.updateRecurringShift, { user_id, ...args })),
  tool(recurring.stopRecurringShift, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.stopRecurringShift, { user_id, ...args })),
  tool(recurring.deleteRecurringShift, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.deleteRecurringShift, { user_id, ...args })),
  tool(recurring.changeRecurringOccurrence, (ctx, user_id, args) =>
    ctx.runMutation(internal.mcpPlans.changeRecurringOccurrence, { user_id, ...args }),
  ),
  tool(specs.listEvents, (ctx, user_id, args) => ctx.runQuery(internal.mcpPlans.listEvents, { user_id, ...args })),
  tool(specs.addEvent, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.addEvent, { user_id, ...args })),
  tool(specs.updateEvent, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.updateEvent, { user_id, ...args })),
  tool(specs.deleteEvent, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.deleteEvent, { user_id, ...args })),
  tool(specs.listPayrollAdjustments, (ctx, user_id, args) => ctx.runQuery(internal.mcpPlans.listPayrollAdjustments, { user_id, ...args })),
  tool(specs.addPayrollAdjustment, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.addPayrollAdjustment, { user_id, ...args })),
  tool(specs.updatePayrollAdjustment, (ctx, user_id, args) =>
    ctx.runMutation(internal.mcpPlans.updatePayrollAdjustment, { user_id, ...args }),
  ),
  tool(specs.deletePayrollAdjustment, (ctx, user_id, args) =>
    ctx.runMutation(internal.mcpPlans.deletePayrollAdjustment, { user_id, ...args }),
  ),
  tool(specs.getSettings, (ctx, user_id) => ctx.runQuery(internal.mcpPlans.getSettings, { user_id })),
  tool(specs.updateSettings, (ctx, user_id, args) => ctx.runMutation(internal.mcpPlans.updateSettings, { user_id, ...args })),
];
