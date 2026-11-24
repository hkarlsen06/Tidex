import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import { resolveDateQuery } from "./lib/mcp/args";
import { checked, fail, jobForShift, jobsOf, live, matchJob, requireUser } from "./lib/mcp/db";
import {
  type ComputedShiftPay,
  computeShiftsWithPay,
  payoutEarningsReport,
  summarizeShiftsByCurrency,
  workedEarningsReport,
} from "./lib/mcp/earnings";
import {
  localNowInTimeZone,
  parseMonth,
  parseStoredPayPeriod,
  payWindowsPaidInMonth,
  weekdayName,
} from "./lib/mcp/payPeriod";
import { eventView } from "./lib/mcp/plans";
import { planOccurrence, type Series, seriesDates, storedEndCondition } from "./lib/mcp/recurring";
import { type McpTool, tool } from "./lib/mcp/registry";
import {
  clockTime,
  endsNextDay,
  movedTimes,
  parseShiftId,
  recurringOccurrenceId,
  shiftTimes,
  storedEndTime,
} from "./lib/mcp/shiftTimes";
import * as specs from "./lib/mcp/shifts";
import { PAYROLL_REVISION } from "./lib/payrollCompatibility";
import { scheduleTimeZone } from "./lib/scheduleTimeZone";
import { overtimeWeekStart } from "./lib/shared/liveActivityPay";
import type { LiveActivityRegularShift } from "./lib/shared/liveActivityScheduling";
import { applicableWageSnapshot, asRecurringShift, asRegularShift, asSnapshot } from "./liveActivities";
import { recurringWrites } from "./recurringShifts";
import { shiftWrites } from "./userShifts";

// The MCP schedule, earnings and shift tools. Each runs for the user the OAuth token names;
// mcp.ts checks the token, scope and arguments first. None of these functions is public.

type ShiftFields = Pick<Doc<"user_shifts">, "id" | "shift_date" | "start_time" | "end_time" | "job_id" | "note">;

function basicShiftOut(shift: ShiftFields, jobs: Doc<"jobs">[]) {
  const job = jobs.find((j) => j.id === shift.job_id);
  const start = clockTime(shift.start_time);
  const end = clockTime(shift.end_time);
  return {
    id: shift.id,
    date: shift.shift_date,
    weekday: weekdayName(shift.shift_date),
    start,
    end,
    ...(endsNextDay(start, end) ? { ends_next_day: true } : {}),
    job_id: shift.job_id,
    job_name: job?.name ?? null,
    currency: job?.currency ?? "kr",
    ...(shift.note ? { note: shift.note } : {}),
  };
}

function scheduleShiftOut(
  computed: ComputedShiftPay,
  oneOffNotes: Map<string, string>,
  recurringNotes: Map<string, Record<string, string>>,
) {
  const start = clockTime(computed.start_time);
  const end = clockTime(computed.end_time);
  const isRecurring = computed.recurring_id !== null;
  const id = isRecurring ? recurringOccurrenceId(computed.recurring_id!, computed.shift_date) : computed.id;
  const note = isRecurring
    ? recurringNotes.get(computed.recurring_id!)?.[computed.shift_date]
    : oneOffNotes.get(computed.id);
  return {
    id,
    date: computed.shift_date,
    weekday: weekdayName(computed.shift_date),
    start,
    end,
    ...(endsNextDay(start, end) ? { ends_next_day: true } : {}),
    job_id: computed.job_id,
    job_name: computed.job_name,
    currency: computed.currency,
    ...(isRecurring ? { recurring_id: computed.recurring_id } : {}),
    ...(note ? { note } : {}),
    duration_hours: computed.duration_hours,
    paid_hours: computed.paid_hours,
    ...(computed.break_minutes > 0 ? { break_minutes: computed.break_minutes } : {}),
    ...(computed.pay_set_up
      ? {
          base_pay: computed.base_pay,
          supplement_pay: computed.supplement_pay,
          gross_pay: computed.gross_pay,
          net_pay: computed.net_pay,
          tax_deducted: computed.tax_deducted,
          effective_tax_percent: computed.effective_tax_percent,
          ...(computed.half_tax_applied ? { half_tax_applied: true } : {}),
          ...(computed.overtime_hours > 0 ? { overtime_hours: computed.overtime_hours } : {}),
          payout_date: computed.payout_date,
          ...(computed.excluded_by_overlap ? { excluded_by_overlap: true } : {}),
        }
      : { pay_set_up: false }),
  };
}

async function userSettingsOf(ctx: QueryCtx, userId: string) {
  return await ctx.db
    .query("user_settings")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .unique();
}

const asSeries = (r: Doc<"recurring_shifts">): Series => ({
  selected_days: r.selected_days as Record<string, string>,
  repeat_interval_weeks: r.repeat_interval_weeks,
  end_condition: storedEndCondition(r.end_condition),
  exclusions: (r.exclusions as string[] | undefined) ?? [],
});

const recurringNotesOf = (r: Doc<"recurring_shifts">) =>
  (r.date_specific_notes as Record<string, string> | undefined) ?? {};

// ---------- Reads ----------

export const getSchedule = internalQuery({
  args: {
    user_id: v.string(),
    month: v.optional(v.string()),
    from: v.optional(v.string()),
    to: v.optional(v.string()),
    job: v.optional(v.string()),
    include_events: v.boolean(),
  },
  handler: async (ctx, args) => {
    const timeZone = await scheduleTimeZone(ctx, args.user_id);
    const { today } = localNowInTimeZone(timeZone);
    const range = checked(() => resolveDateQuery({ month: args.month, from: args.from, to: args.to }, today, "two_weeks"));

    const [jobs, settings, rawSnapshots, rawShifts, rawRecurring] = await Promise.all([
      jobsOf(ctx, args.user_id),
      userSettingsOf(ctx, args.user_id),
      ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", args.user_id)).collect(),
      ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) =>
          q.eq("user_id", args.user_id).gte("shift_date", overtimeWeekStart(range.from)).lte("shift_date", range.to),
        )
        .collect(),
      ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", args.user_id)).collect(),
    ]);

    const filterJobId = args.job !== undefined ? matchJob(jobs, args.job, { includeArchived: true }).id : undefined;
    const snapshots = live(rawSnapshots).map(asSnapshot);
    const liveShifts = live(rawShifts);
    const liveRecurring = live(rawRecurring);

    const oneOffNotes = new Map<string, string>();
    for (const s of liveShifts) {
      if (s.note) oneOffNotes.set(s.id, s.note);
    }
    const recurringNotes = new Map<string, Record<string, string>>();
    for (const r of liveRecurring) {
      const notes = recurringNotesOf(r);
      if (Object.keys(notes).length > 0) recurringNotes.set(r.id, notes);
    }

    const computed = computeShiftsWithPay({
      from: range.from,
      to: range.to,
      regular: liveShifts.map(asRegularShift),
      recurring: liveRecurring.map(asRecurringShift),
      jobs,
      snapshotFor: (shift) => applicableWageSnapshot(shift, snapshots),
      fallbackPayrollDay: settings?.payroll_day,
      fallbackHalfTaxMonth: settings?.half_tax_month,
    });

    const visibleShifts = filterJobId
      ? computed.shifts.filter((s) => s.job_id === filterJobId)
      : computed.shifts;
    const unpaidCount = visibleShifts.filter((s) => !s.pay_set_up).length;

    let events: ReturnType<typeof eventView>[] | undefined;
    if (args.include_events) {
      const rawEvents = live(
        await ctx.db.query("events").withIndex("by_user_revision", (q) => q.eq("user_id", args.user_id)).collect(),
      );
      events = rawEvents
        .filter((e) => e.start_date <= range.to && e.end_date >= range.from)
        .sort((a, b) => a.start_date.localeCompare(b.start_date) || (a.start_time ?? "").localeCompare(b.start_time ?? ""))
        .map(eventView);
    }

    return {
      from: range.from,
      to: range.to,
      today,
      time_zone: timeZone,
      summary: summarizeShiftsByCurrency(visibleShifts),
      shifts: visibleShifts.map((s) => scheduleShiftOut(s, oneOffNotes, recurringNotes)),
      ...(events !== undefined ? { events } : {}),
      ...(unpaidCount > 0 ? { shifts_without_pay_setup: unpaidCount } : {}),
    };
  },
});

export const getEarnings = internalQuery({
  args: {
    user_id: v.string(),
    by: v.union(v.literal("worked"), v.literal("payout")),
    month: v.optional(v.string()),
    from: v.optional(v.string()),
    to: v.optional(v.string()),
    job: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const timeZone = await scheduleTimeZone(ctx, args.user_id);
    const { today } = localNowInTimeZone(timeZone);

    const [jobs, settings, rawSnapshots, rawRecurring, rawAdjustments] = await Promise.all([
      jobsOf(ctx, args.user_id),
      userSettingsOf(ctx, args.user_id),
      ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", args.user_id)).collect(),
      ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", args.user_id)).collect(),
      ctx.db.query("payroll_adjustments").withIndex("by_user_revision", (q) => q.eq("user_id", args.user_id)).collect(),
    ]);

    const filterJobId = args.job !== undefined ? matchJob(jobs, args.job, { includeArchived: true }).id : undefined;
    const snapshots = live(rawSnapshots).map(asSnapshot);
    const recurring = live(rawRecurring).map(asRecurringShift);
    const adjustments = live(rawAdjustments);

    const snapshotFor = (shift: LiveActivityRegularShift) => applicableWageSnapshot(shift, snapshots);
    const snapshotForJobDate = (jobId: string, date: string) =>
      applicableWageSnapshot({ user_id: args.user_id, job_id: jobId, shift_date: date } as LiveActivityRegularShift, snapshots);

    if (args.by === "payout") {
      const parsedMonth = checked(() => parseMonth(args.month ?? today.slice(0, 7)));
      const targetJobs = filterJobId ? jobs.filter((j) => j.id === filterJobId) : jobs;
      const windowBounds: string[] = [];
      for (const job of targetJobs) {
        const period = parseStoredPayPeriod(job.pay_period);
        const payrollDay = job.payroll_day ?? settings?.payroll_day ?? 15;
        for (const w of payWindowsPaidInMonth(period, payrollDay, parsedMonth.year, parsedMonth.month)) {
          windowBounds.push(w.start, w.end);
        }
      }
      windowBounds.sort();
      const regular =
        windowBounds.length === 0
          ? []
          : live(
              await ctx.db
                .query("user_shifts")
                .withIndex("by_user_shift_date", (q) =>
                  q
                    .eq("user_id", args.user_id)
                    .gte("shift_date", overtimeWeekStart(windowBounds[0]!))
                    .lte("shift_date", windowBounds.at(-1)!),
                )
                .collect(),
            ).map(asRegularShift);

      return payoutEarningsReport({
        monthKey: parsedMonth.monthKey,
        year: parsedMonth.year,
        month: parsedMonth.month,
        monthFrom: parsedMonth.from,
        monthTo: parsedMonth.to,
        regular,
        recurring,
        jobs,
        adjustments,
        snapshotFor,
        snapshotForJobDate,
        fallbackPayrollDay: settings?.payroll_day,
        fallbackHalfTaxMonth: settings?.half_tax_month,
        filterJobId,
      });
    }

    const range = checked(() => resolveDateQuery({ month: args.month, from: args.from, to: args.to }, today, "current_month"));
    const regular = live(
      await ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) =>
          q.eq("user_id", args.user_id).gte("shift_date", overtimeWeekStart(range.from)).lte("shift_date", range.to),
        )
        .collect(),
    ).map(asRegularShift);

    return workedEarningsReport({
      from: range.from,
      to: range.to,
      regular,
      recurring,
      jobs,
      adjustments,
      snapshotFor,
      snapshotForJobDate,
      fallbackPayrollDay: settings?.payroll_day,
      fallbackHalfTaxMonth: settings?.half_tax_month,
      filterJobId,
    });
  },
});

// ---------- Writes ----------

export const addShifts = internalMutation({
  args: {
    user_id: v.string(),
    shifts: v.array(
      v.object({
        date: v.string(),
        start: v.string(),
        end: v.string(),
        job: v.optional(v.string()),
        note: v.optional(v.string()),
      }),
    ),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const jobs = await jobsOf(ctx, user.id);

    // Pre-fetch existing shifts on every unique date in the batch so retries and duplicates stay idempotent.
    const dates = [...new Set(args.shifts.map((s) => s.date))];
    const existingByDate = new Map<string, ShiftFields[]>();
    for (const date of dates) {
      existingByDate.set(
        date,
        live(
          await ctx.db
            .query("user_shifts")
            .withIndex("by_user_shift_date", (q) => q.eq("user_id", user.id).eq("shift_date", date))
            .collect(),
        ),
      );
    }

    const resultShifts: ReturnType<typeof basicShiftOut>[] = [];
    let added = 0;
    let alreadyExisted = 0;

    for (const draft of args.shifts) {
      const job = await jobForShift(ctx, user.id, draft.job);
      const times = checked(() => shiftTimes(draft.start, draft.end));
      const dayShifts = existingByDate.get(draft.date) ?? [];
      const existing = dayShifts.find((s) => {
        const start = clockTime(s.start_time);
        return s.job_id === job.id && start === times.start_time && storedEndTime(clockTime(s.end_time), start) === times.end_time;
      });
      if (existing !== undefined) {
        alreadyExisted += 1;
        resultShifts.push(basicShiftOut(existing, jobs));
        continue;
      }
      const note = draft.note?.trim();
      const { row } = await shiftWrites.insert(ctx, user.id, {
        row: {
          id: crypto.randomUUID(),
          job_id: job.id,
          shift_date: draft.date,
          ...times,
          ...(note ? { note } : {}),
        },
        payroll_revision: PAYROLL_REVISION,
      });
      const inserted = row as ShiftFields;
      dayShifts.push(inserted);
      existingByDate.set(draft.date, dayShifts);
      added += 1;
      resultShifts.push(basicShiftOut(inserted, jobs));
    }

    return { shifts: resultShifts, added, already_existed: alreadyExisted };
  },
});

export const updateShift = internalMutation({
  args: {
    user_id: v.string(),
    id: v.string(),
    date: v.optional(v.string()),
    start: v.optional(v.string()),
    end: v.optional(v.string()),
    job: v.optional(v.string()),
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const jobs = await jobsOf(ctx, user.id);
    const parsedId = checked(() => parseShiftId(args.id));

    if (parsedId.kind === "one_off") {
      const prev = await ctx.db
        .query("user_shifts")
        .withIndex("by_uuid", (q) => q.eq("id", parsedId.shiftId))
        .unique();
      if (prev === null || prev.user_id !== user.id || prev.deleted_at !== undefined) {
        fail("No shift with that id. Use an id from get_schedule.");
      }
      const set: Record<string, unknown> = {};
      const clear: string[] = [];
      if (args.date !== undefined && args.date !== prev.shift_date) set.shift_date = args.date;
      if (args.start !== undefined || args.end !== undefined) {
        const moved = checked(() => movedTimes({ start: prev.start_time, end: prev.end_time }, args.start, args.end));
        const start = clockTime(prev.start_time);
        if (moved.start_time !== start || moved.end_time !== storedEndTime(clockTime(prev.end_time), start)) {
          Object.assign(set, moved);
        }
      }
      if (args.job !== undefined) {
        const targetJob = await jobForShift(ctx, user.id, args.job);
        if (targetJob.id !== prev.job_id) set.job_id = targetJob.id;
      }
      if (args.note !== undefined) {
        const note = args.note.trim();
        if (note === "" && prev.note !== undefined) clear.push("note");
        else if (note !== "" && note !== prev.note) set.note = note;
      }
      if (Object.keys(set).length === 0 && clear.length === 0) {
        return { shift: basicShiftOut(prev, jobs) };
      }
      const result = await shiftWrites.update(ctx, user.id, {
        id: prev.id,
        expected_revision: prev.revision,
        set,
        clear,
        payroll_revision: PAYROLL_REVISION,
      });
      if (result.status !== "ok") fail("The shift changed during the update. Try again.");
      return { shift: basicShiftOut(result.row as ShiftFields, jobs) };
    }

    // Recurring occurrence update: note-only stays on the series; date/time/job detaches to a one-off shift.
    const seriesRow = await ctx.db
      .query("recurring_shifts")
      .withIndex("by_uuid", (q) => q.eq("id", parsedId.recurringId))
      .unique();
    if (seriesRow === null || seriesRow.user_id !== user.id || seriesRow.deleted_at !== undefined) {
      fail("No recurring shift with that id. Use an id from get_schedule.");
    }
    const series = asSeries(seriesRow);
    if (!seriesDates(series, parsedId.date, parsedId.date).includes(parsedId.date)) {
      fail(`${parsedId.date} is not an active date of this series. Call get_schedule to see current dates.`);
    }

    const targetJob =
      args.job !== undefined ? await jobForShift(ctx, user.id, args.job) : null;
    const jobChanged = targetJob !== null && targetJob.id !== seriesRow.job_id;
    const moves = args.date !== undefined || args.start !== undefined || args.end !== undefined || jobChanged;

    const plan = checked(() =>
      planOccurrence(
        {
          start_time: seriesRow.start_time,
          end_time: seriesRow.end_time,
          exclusions: series.exclusions,
          date_specific_notes: recurringNotesOf(seriesRow),
        },
        parsedId.date,
        moves
          ? { kind: "change", date: args.date, start: args.start, end: args.end, note: args.note, forceDetach: jobChanged }
          : { kind: "note", note: args.note ?? "" },
      ),
    );

    const set: Record<string, unknown> = {};
    const clear: string[] = [];
    if (plan.exclusions !== undefined && JSON.stringify(plan.exclusions) !== JSON.stringify(seriesRow.exclusions)) {
      set.exclusions = plan.exclusions;
    }
    if (plan.date_specific_notes !== undefined) {
      if (plan.date_specific_notes === null) {
        if (seriesRow.date_specific_notes !== undefined) clear.push("date_specific_notes");
      } else if (JSON.stringify(plan.date_specific_notes) !== JSON.stringify(seriesRow.date_specific_notes)) {
        set.date_specific_notes = plan.date_specific_notes;
      }
    }

    if (Object.keys(set).length > 0 || clear.length > 0) {
      const updated = await recurringWrites.update(ctx, user.id, {
        id: seriesRow.id,
        expected_revision: seriesRow.revision,
        set,
        clear,
        payroll_revision: PAYROLL_REVISION,
      });
      if (updated.status !== "ok") fail("The recurring shift changed during the update. Try again.");
    }

    if (plan.shift !== undefined) {
      const shiftJob = targetJob ?? (await jobForShift(ctx, user.id, seriesRow.job_id));
      const { row } = await shiftWrites.insert(ctx, user.id, {
        row: { id: crypto.randomUUID(), job_id: shiftJob.id, ...plan.shift },
        payroll_revision: PAYROLL_REVISION,
      });
      return { shift: basicShiftOut(row as ShiftFields, jobs), detached_from_recurring: true };
    }

    const updatedNote = (plan.date_specific_notes ?? recurringNotesOf(seriesRow))[parsedId.date];
    const seriesJob = jobs.find((j) => j.id === seriesRow.job_id);
    const start = clockTime(seriesRow.start_time);
    const end = clockTime(seriesRow.end_time);
    return {
      shift: {
        id: args.id,
        date: parsedId.date,
        weekday: weekdayName(parsedId.date),
        start,
        end,
        ...(endsNextDay(start, end) ? { ends_next_day: true } : {}),
        job_id: seriesRow.job_id,
        job_name: seriesJob?.name ?? null,
        currency: seriesJob?.currency ?? "kr",
        recurring_id: seriesRow.id,
        ...(updatedNote ? { note: updatedNote } : {}),
      },
    };
  },
});

export const deleteShifts = internalMutation({
  args: { user_id: v.string(), ids: v.array(v.string()) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const jobs = await jobsOf(ctx, user.id);

    const oneOffRows: Doc<"user_shifts">[] = [];
    const recurringSkips = new Map<string, string[]>();

    for (const id of args.ids) {
      const parsed = checked(() => parseShiftId(id));
      if (parsed.kind === "one_off") {
        const row = await ctx.db
          .query("user_shifts")
          .withIndex("by_uuid", (q) => q.eq("id", parsed.shiftId))
          .unique();
        if (row === null || row.user_id !== user.id || row.deleted_at !== undefined) {
          fail(`No shift with id "${id}". Use ids from get_schedule.`);
        }
        oneOffRows.push(row);
      } else {
        const list = recurringSkips.get(parsed.recurringId) ?? [];
        list.push(parsed.date);
        recurringSkips.set(parsed.recurringId, list);
      }
    }

    const deleted: Record<string, unknown>[] = [];

    for (const prev of oneOffRows) {
      const result = await shiftWrites.remove(ctx, user.id, {
        id: prev.id,
        expected_revision: prev.revision,
        payroll_revision: PAYROLL_REVISION,
      });
      if (result.status !== "ok") fail("A shift changed during deletion. Try again.");
      deleted.push(basicShiftOut(result.row as ShiftFields, jobs));
    }

    for (const [recurringId, dates] of recurringSkips.entries()) {
      const seriesRow = await ctx.db
        .query("recurring_shifts")
        .withIndex("by_uuid", (q) => q.eq("id", recurringId))
        .unique();
      if (seriesRow === null || seriesRow.user_id !== user.id || seriesRow.deleted_at !== undefined) {
        fail(`No recurring shift with id "${recurringId}". Use ids from get_schedule.`);
      }
      const series = asSeries(seriesRow);
      for (const date of dates) {
        if (!seriesDates(series, date, date).includes(date)) {
          fail(`${date} is not an active date of this series. Call get_schedule to see current dates.`);
        }
      }
      const nextExclusions = [...new Set([...series.exclusions, ...dates])].sort();
      const updated = await recurringWrites.update(ctx, user.id, {
        id: seriesRow.id,
        expected_revision: seriesRow.revision,
        set: { exclusions: nextExclusions },
        clear: [],
        payroll_revision: PAYROLL_REVISION,
      });
      if (updated.status !== "ok") fail("A recurring shift changed during deletion. Try again.");
      const job = jobs.find((j) => j.id === seriesRow.job_id);
      const start = clockTime(seriesRow.start_time);
      const end = clockTime(seriesRow.end_time);
      for (const date of dates) {
        deleted.push({
          id: recurringOccurrenceId(seriesRow.id, date),
          date,
          weekday: weekdayName(date),
          start,
          end,
          job_id: seriesRow.job_id,
          job_name: job?.name ?? null,
          recurring_id: seriesRow.id,
          skipped: true,
        });
      }
    }

    return { deleted, count: deleted.length };
  },
});

export const shiftTools: McpTool[] = [
  tool(specs.getSchedule, (ctx, user_id, args) => ctx.runQuery(internal.mcpShifts.getSchedule, { user_id, ...args })),
  tool(specs.getEarnings, (ctx, user_id, args) => ctx.runQuery(internal.mcpShifts.getEarnings, { user_id, ...args })),
  tool(specs.addShifts, (ctx, user_id, args) => ctx.runMutation(internal.mcpShifts.addShifts, { user_id, ...args })),
  tool(specs.updateShift, (ctx, user_id, args) => ctx.runMutation(internal.mcpShifts.updateShift, { user_id, ...args })),
  tool(specs.deleteShifts, (ctx, user_id, args) => ctx.runMutation(internal.mcpShifts.deleteShifts, { user_id, ...args })),
];
