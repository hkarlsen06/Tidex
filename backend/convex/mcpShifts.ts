import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import { checked, fail, jobForShift, jobsOf, live, requireUser } from "./lib/mcp/db";
import { shiftEarnings } from "./lib/mcp/earnings";
import { type McpTool, tool } from "./lib/mcp/registry";
import { addDays, clockTime, endsNextDay, movedTimes, shiftTimes, storedEndTime } from "./lib/mcp/shiftTimes";
import * as specs from "./lib/mcp/shifts";
import { PAYROLL_REVISION } from "./lib/payrollCompatibility";
import { scheduleTimeZone } from "./lib/scheduleTimeZone";
import { overtimeWeekStart } from "./lib/shared/liveActivityPay";
import { projectedRecurringShifts } from "./lib/shared/liveActivityScheduling";
import { applicableWageSnapshot, asRecurringShift, asRegularShift, asSnapshot } from "./liveActivities";
import { shiftWrites } from "./userShifts";

// The MCP shift tools. Each runs for the user the OAuth token names; mcp.ts checks the
// token, the scope and the arguments first. None of these functions is public.

type ShiftFields = Pick<Doc<"user_shifts">, "id" | "revision" | "shift_date" | "start_time" | "end_time" | "job_id" | "note">;

function oneOff(shift: ShiftFields, jobs: Doc<"jobs">[]) {
  return {
    kind: "one_off" as const,
    shift_id: shift.id,
    revision: shift.revision,
    date: shift.shift_date,
    start: clockTime(shift.start_time),
    end: clockTime(shift.end_time),
    ends_next_day: endsNextDay(shift.start_time, shift.end_time),
    job_id: shift.job_id,
    job_name: jobs.find((j) => j.id === shift.job_id)?.name ?? null,
    note: shift.note ?? null,
  };
}

// ---------- Reads ----------

export const listShifts = internalQuery({
  args: { user_id: v.string(), from: v.string(), to: v.string() },
  handler: async (ctx, { user_id, from, to }) => {
    const jobs = await jobsOf(ctx, user_id);
    const dates: string[] = [];
    for (let date = from; date <= to; date = addDays(date, 1)) dates.push(date);
    const oneOffs = live(
      await ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) => q.eq("user_id", user_id).gte("shift_date", from).lte("shift_date", to))
        .collect(),
    ).map((s) => oneOff(s, jobs));
    const recurring = live(
      await ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", user_id)).collect(),
    ).flatMap((r) =>
      projectedRecurringShifts([asRecurringShift(r)], dates).map((s) => ({
        kind: "recurring" as const,
        recurring_shift_id: r.id,
        date: s.shift_date,
        start: clockTime(s.start_time),
        end: clockTime(s.end_time),
        ends_next_day: endsNextDay(s.start_time, s.end_time),
        job_id: r.job_id,
        job_name: jobs.find((j) => j.id === r.job_id)?.name ?? null,
        note: (r.date_specific_notes as Record<string, string> | undefined)?.[s.shift_date] ?? null,
      })),
    );
    return {
      time_zone: await scheduleTimeZone(ctx, user_id),
      shifts: [...oneOffs, ...recurring].sort((a, b) => a.date.localeCompare(b.date) || a.start.localeCompare(b.start)),
    };
  },
});

export const earnings = internalQuery({
  args: { user_id: v.string(), from: v.string(), to: v.string() },
  handler: async (ctx, { user_id, from, to }) => {
    const jobs = await jobsOf(ctx, user_id);
    const snapshots = live(
      await ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", user_id)).collect(),
    ).map(asSnapshot);
    const regular = live(
      await ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) =>
          q.eq("user_id", user_id).gte("shift_date", overtimeWeekStart(from)).lte("shift_date", to),
        )
        .collect(),
    ).map(asRegularShift);
    const recurring = live(
      await ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", user_id)).collect(),
    ).map(asRecurringShift);
    return {
      from,
      to,
      ...shiftEarnings({
        from,
        to,
        regular,
        recurring,
        snapshotFor: (shift) => applicableWageSnapshot(shift, snapshots),
        currencyFor: (jobId) => jobs.find((j) => j.id === jobId)?.currency ?? "NOK",
      }),
    };
  },
});

// ---------- Writes ----------

export const addShift = internalMutation({
  args: {
    user_id: v.string(),
    date: v.string(),
    start: v.string(),
    end: v.string(),
    job_id: v.optional(v.string()),
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const job = await jobForShift(ctx, user.id, args.job_id);
    const times = checked(() => shiftTimes(args.start, args.end));
    const jobs = await jobsOf(ctx, user.id);
    // A retried call finds the shift its first attempt added.
    const existing = live(
      await ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) => q.eq("user_id", user.id).eq("shift_date", args.date))
        .collect(),
    ).find((s) => {
      const start = clockTime(s.start_time);
      // Older rows may store a midnight end as 00:00.
      return s.job_id === job.id && start === times.start_time && storedEndTime(clockTime(s.end_time), start) === times.end_time;
    });
    if (existing !== undefined) return { shift: oneOff(existing, jobs), already_existed: true };
    const note = args.note?.trim();
    const { row } = await shiftWrites.insert(ctx, user.id, {
      row: {
        id: crypto.randomUUID(),
        job_id: job.id,
        shift_date: args.date,
        ...times,
        ...(note ? { note } : {}),
      },
      payroll_revision: PAYROLL_REVISION,
    });
    return { shift: oneOff(row as ShiftFields, jobs), already_existed: false };
  },
});

const STALE = "The shift changed since you listed it. Call list_shifts again and use the new revision.";
const NOT_FOUND = "No one-off shift with that shift_id. Use a shift_id from list_shifts; recurring shifts can only be changed in the Tidex app.";

async function ownShift(ctx: QueryCtx, userId: string, shiftId: string, revision: number) {
  const shift = await ctx.db.query("user_shifts").withIndex("by_uuid", (q) => q.eq("id", shiftId)).unique();
  if (shift === null || shift.user_id !== userId || shift.deleted_at !== undefined) fail(NOT_FOUND);
  if (shift.revision !== revision) fail(STALE);
  return shift;
}

export const updateShift = internalMutation({
  args: {
    user_id: v.string(),
    shift_id: v.string(),
    revision: v.number(),
    date: v.optional(v.string()),
    start: v.optional(v.string()),
    end: v.optional(v.string()),
    job_id: v.optional(v.string()),
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await ownShift(ctx, user.id, args.shift_id, args.revision);
    const set: Record<string, unknown> = {};
    const clear: string[] = [];
    // Only what differs from the stored shift is written.
    if (args.date !== undefined && args.date !== prev.shift_date) set.shift_date = args.date;
    if (args.start !== undefined || args.end !== undefined) {
      const moved = checked(() => movedTimes({ start: prev.start_time, end: prev.end_time }, args.start, args.end));
      const start = clockTime(prev.start_time);
      if (moved.start_time !== start || moved.end_time !== storedEndTime(clockTime(prev.end_time), start)) {
        Object.assign(set, moved);
      }
    }
    if (args.job_id !== undefined && args.job_id !== prev.job_id) set.job_id = (await jobForShift(ctx, user.id, args.job_id)).id;
    if (args.note !== undefined) {
      const note = args.note.trim();
      if (note === "" && prev.note !== undefined) clear.push("note");
      else if (note !== "" && note !== prev.note) set.note = note;
    }
    // Nothing to change keeps the revision the agent holds.
    if (Object.keys(set).length === 0 && clear.length === 0) return { shift: oneOff(prev, await jobsOf(ctx, user.id)) };
    const result = await shiftWrites.update(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      set,
      clear,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail(STALE);
    return { shift: oneOff(result.row as ShiftFields, await jobsOf(ctx, user.id)) };
  },
});

export const deleteShift = internalMutation({
  args: { user_id: v.string(), shift_id: v.string(), revision: v.number() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await ownShift(ctx, user.id, args.shift_id, args.revision);
    const result = await shiftWrites.remove(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail(STALE);
    return { deleted: oneOff(result.row as ShiftFields, await jobsOf(ctx, user.id)) };
  },
});

export const shiftTools: McpTool[] = [
  tool(specs.listShifts, (ctx, user_id, args) => ctx.runQuery(internal.mcpShifts.listShifts, { user_id, ...args })),
  tool(specs.getEarnings, (ctx, user_id, args) => ctx.runQuery(internal.mcpShifts.earnings, { user_id, ...args })),
  tool(specs.addShift, (ctx, user_id, args) => ctx.runMutation(internal.mcpShifts.addShift, { user_id, ...args })),
  tool(specs.updateShift, (ctx, user_id, args) => ctx.runMutation(internal.mcpShifts.updateShift, { user_id, ...args })),
  tool(specs.deleteShift, (ctx, user_id, args) => ctx.runMutation(internal.mcpShifts.deleteShift, { user_id, ...args })),
];
