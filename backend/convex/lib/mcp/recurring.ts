import { generateVirtualShiftsForMonth, resolveEndWindow, toISODate } from "../shared/recurring/utils";
import {
  adds,
  allowOnly,
  type Args,
  boolean,
  date,
  destructive,
  endTime,
  integer,
  jobRef,
  list,
  nearDate,
  optional,
  optionalString,
  requiredString,
  time,
} from "./args";
import { WEEKDAYS } from "./payPeriod";
import type { ToolSpec } from "./registry";
import { addDays, clockTime, endsNextDay, MINUTES_PER_DAY, minutes, movedTimes, parseDate, parseTime, shiftTimes, ToolError } from "./shiftTimes";

// The recurring shift tools and the series columns they write. Values match the iOS app's
// Codable sync format so recurring_shifts stays decodable.

export { WEEKDAYS };

/** recurring_shifts.end_condition as the app writes it. Omitted means the series never ends. */
export type EndCondition = { type: "months"; value: number } | { type: "years"; value: number } | { type: "end_date"; date: string };

/** The columns that decide which dates a series has. */
export type Series = {
  /** Weekday "0" (Sunday) to "6" to the first date on that weekday. */
  selected_days: Record<string, string>;
  /** 0 is every week, 1 every second week, up to 8. */
  repeat_interval_weeks: number;
  end_condition: EndCondition | null;
  exclusions: string[];
};

/** Stored end_condition, including the older {type: "end_date", value} form, as EndCondition. */
export function storedEndCondition(stored: unknown): EndCondition | null {
  const e = stored as { type?: string; value?: unknown; date?: unknown } | null | undefined;
  if (e?.type === "months" || e?.type === "years") return { type: e.type, value: Number(e.value) };
  if (e?.type === "end_date") return { type: "end_date", date: String(e.date ?? e.value) };
  return null;
}

/** The series' dates from `from` to `to`, both included, as the app's generator gives them. */
export function seriesDates(series: Series, from: string, to: string): string[] {
  const draft = { ...series, start_time: "", end_time: "", repeat_interval_weeks: series.repeat_interval_weeks as 0 };
  const dates: string[] = [];
  for (let month = from.slice(0, 7); month <= to.slice(0, 7); month = addDays(`${month}-28`, 7).slice(0, 7)) {
    const [year, m] = month.split("-").map(Number);
    for (const shift of generateVirtualShiftsForMonth({ year: year!, month: m! }, draft)) {
      if (shift.date >= from && shift.date <= to) dates.push(shift.date);
    }
  }
  return dates.sort();
}

/** True when `a` and `b` put shifts at the same times on the same dates, skipped dates aside. */
export function sameSeries(a: Series & { start_time: string; end_time: string }, b: Series & { start_time: string; end_time: string }) {
  const days = (s: Series) => JSON.stringify(Object.entries(s.selected_days).sort());
  return (
    clockTime(a.start_time) === clockTime(b.start_time) &&
    midnightAsZero(clockTime(a.end_time)) === midnightAsZero(clockTime(b.end_time)) &&
    a.repeat_interval_weeks === b.repeat_interval_weeks &&
    days(a) === days(b) &&
    JSON.stringify(a.end_condition) === JSON.stringify(b.end_condition)
  );
}

export const firstDate = (series: Pick<Series, "selected_days">) => Object.values(series.selected_days).sort()[0]!;

/** The series' last possible date, or null when it never ends. */
export function lastDate(series: Pick<Series, "selected_days" | "end_condition">): string | null {
  if (series.end_condition === null) return null;
  const window = resolveEndWindow(series.selected_days, series.end_condition);
  return window === null ? null : toISODate(window.maxDate);
}

/** Where the app looks for clashes when it adds a series: to its end, or two years ahead. */
export function previewEnd(series: Pick<Series, "selected_days" | "end_condition">): string {
  return lastDate(series) ?? lastDate({ ...series, end_condition: { type: "years", value: 2 } })!;
}

/** An older series may store a midnight end as 00:00, which means the same as 24:00. */
const midnightAsZero = (end: string) => (end === "24:00" ? "00:00" : end);

/** Clean formatted view of a recurring series, used by get_overview and save_recurring_shift. */
export function recurringView(
  r: {
    id: string;
    job_id: string;
    start_time: string;
    end_time: string;
    repeat_interval_weeks: number;
    selected_days: unknown;
    end_condition?: unknown;
    exclusions?: unknown;
    date_specific_notes?: unknown;
  },
  jobName: string | null,
) {
  const series: Series = {
    selected_days: r.selected_days as Record<string, string>,
    repeat_interval_weeks: r.repeat_interval_weeks,
    end_condition: storedEndCondition(r.end_condition),
    exclusions: (r.exclusions as string[] | undefined) ?? [],
  };
  const notes = (r.date_specific_notes as Record<string, string> | undefined) ?? {};
  const skipped = [...series.exclusions].sort();
  const last = lastDate(series);
  return {
    id: r.id,
    job_id: r.job_id,
    job_name: jobName,
    start: clockTime(r.start_time),
    end: clockTime(r.end_time),
    ...(endsNextDay(r.start_time, r.end_time) ? { ends_next_day: true } : {}),
    every_weeks: r.repeat_interval_weeks + 1,
    days: Object.entries(series.selected_days)
      .sort(([, a], [, b]) => a.localeCompare(b))
      .map(([weekday, first_date]) => ({ weekday: WEEKDAYS[Number(weekday)], first_date })),
    end_date: last,
    ...(skipped.length > 0 ? { skipped_dates: skipped } : {}),
    ...(Object.keys(notes).length > 0 ? { notes } : {}),
  };
}

/** first_dates as selected_days: each date is the first shift on its weekday. */
function parseFirstDates(value: unknown): Record<string, string> {
  const dates = list(value, "first_dates", 7).map((d) => nearDate(d, "first_dates"));
  if (dates.length === 0) throw new ToolError("first_dates needs at least one date.");
  const days: Record<string, string> = {};
  for (const d of dates) {
    const weekday = String(new Date(`${d}T00:00:00Z`).getUTCDay());
    if (days[weekday] !== undefined) throw new ToolError(`first_dates has two ${WEEKDAYS[Number(weekday)]}s. Give one date per weekday.`);
    days[weekday] = d;
  }
  return days;
}

/** Parses flat end parameters into an EndCondition update (undefined = unchanged, null = never ends). */
function parseFlatEnd(args: Args): { value: EndCondition | null } | undefined {
  const endDate = optional(args.end_date, (v) => nearDate(v, "end_date"));
  const endMonths = optional(args.end_after_months, (v) => integer(v, "end_after_months", 1, 24));
  const endYears = optional(args.end_after_years, (v) => integer(v, "end_after_years", 1, 5));
  const neverEnds = optional(args.never_ends, (v) => boolean(v, "never_ends"));
  if (neverEnds === false) throw new ToolError("never_ends can only be true. Pass end_date, end_after_months or end_after_years to set an end.");

  const chosen = [endDate !== undefined, endMonths !== undefined, endYears !== undefined, neverEnds === true].filter(Boolean).length;
  if (chosen > 1) throw new ToolError("Give at most one of end_date, end_after_months, end_after_years or never_ends.");
  if (chosen === 0) return undefined;
  if (neverEnds === true) return { value: null };
  if (endDate !== undefined) return { value: { type: "end_date", date: endDate } };
  if (endMonths !== undefined) return { value: { type: "months", value: endMonths } };
  return { value: { type: "years", value: endYears! } };
}

/** A series that has at least its first date. */
export function checkSeries(series: Pick<Series, "selected_days" | "end_condition">) {
  const last = lastDate(series);
  if (last !== null && last < firstDate(series)) {
    throw new ToolError("The series would end before its first date. Delete it with delete_recurring_shift instead.");
  }
}

const everyWeeks = (value: unknown) => integer(value, "every_weeks", 1, 9) - 1;

const firstDatesSchema = {
  type: "array",
  items: date,
  minItems: 1,
  maxItems: 7,
  description: "First shift date for each weekday the series repeats on (one date per weekday).",
};

export const saveRecurringShift = {
  definition: {
    name: "save_recurring_shift",
    title: "Create or update recurring shift",
    description:
      "Creates a repeating shift series (omit id) or updates/stops an existing series (pass id from get_overview or a shift's recurring_id). " +
      "When creating: pass first_dates, start and end (overlapping existing shifts are automatically skipped). " +
      "When updating: pass id plus only what changes; pass end_date to stop future shifts after that date while keeping past ones. " +
      "To edit or delete a single date of a series, use update_shift or delete_shifts with that date's shift id from get_schedule.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Recurring series ID to update. Omit to create a new series." },
        first_dates: firstDatesSchema,
        start: time,
        end: endTime,
        every_weeks: { type: "integer", minimum: 1, maximum: 9, description: "Repeat interval in weeks: 1 = weekly (default), 2 = every 2 weeks, up to 9." },
        end_date: { ...date, description: "Last date included in the series (YYYY-MM-DD)." },
        end_after_months: { type: "integer", minimum: 1, maximum: 24, description: "Stop after this many months from the earliest first date." },
        end_after_years: { type: "integer", minimum: 1, maximum: 5, description: "Stop after this many years from the earliest first date." },
        never_ends: { type: "boolean", enum: [true], description: "Pass true to remove an existing end date so the series repeats indefinitely." },
        job: jobRef,
        unskip_dates: { type: "array", items: date, maxItems: 100, description: "Skipped dates to restore to the series (update only)." },
      },
      additionalProperties: false,
    },
    annotations: { title: "Create or update recurring shift", ...adds },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, [
      "id",
      "first_dates",
      "start",
      "end",
      "every_weeks",
      "end_date",
      "end_after_months",
      "end_after_years",
      "never_ends",
      "job",
      "unskip_dates",
    ]);
    const id = optionalString(args.id, "id");
    const endUpdate = parseFlatEnd(args);

    if (id === undefined) {
      if (args.unskip_dates !== undefined && args.unskip_dates !== null) {
        throw new ToolError("unskip_dates applies only when updating an existing series with id.");
      }
      const series = {
        selected_days: parseFirstDates(args.first_dates),
        ...shiftTimes(parseTime(args.start, "start"), parseTime(args.end, "end", true)),
        repeat_interval_weeks: optional(args.every_weeks, everyWeeks) ?? 0,
        end_condition: endUpdate?.value ?? null,
      };
      checkSeries(series);
      return { mode: "create" as const, ...series, job: optionalString(args.job, "job") };
    }

    const parsed = {
      selected_days: optional(args.first_dates, parseFirstDates),
      start: optional(args.start, (v) => parseTime(v, "start")),
      end: optional(args.end, (v) => parseTime(v, "end", true)),
      repeat_interval_weeks: optional(args.every_weeks, everyWeeks),
      end_condition: endUpdate,
      job: optionalString(args.job, "job"),
      unskip_dates: optional(args.unskip_dates, (v) => list(v, "unskip_dates", 100).map((d) => parseDate(d, "unskip_dates"))),
    };
    if (Object.values(parsed).every((v) => v === undefined)) {
      throw new ToolError("Give at least one field to update (first_dates, start, end, every_weeks, end_date, never_ends, job or unskip_dates).");
    }
    return { mode: "update" as const, id, ...parsed };
  },
} satisfies ToolSpec;

/** A stored series with an update applied: the columns to set and to clear. */
export function seriesUpdate(
  prev: Series & { start_time: string; end_time: string },
  change: {
    selected_days?: Record<string, string>;
    start?: string;
    end?: string;
    repeat_interval_weeks?: number;
    end_condition?: { value: EndCondition | null };
    unskip_dates?: string[];
  },
) {
  const set: Record<string, unknown> = {};
  const clear: string[] = [];
  if (change.start !== undefined || change.end !== undefined) {
    const moved = movedTimes({ start: prev.start_time, end: prev.end_time }, change.start, change.end);
    if (moved.start_time !== clockTime(prev.start_time)) set.start_time = moved.start_time;
    if (midnightAsZero(moved.end_time) !== midnightAsZero(clockTime(prev.end_time))) set.end_time = moved.end_time;
  }
  if (change.selected_days !== undefined && JSON.stringify(sortedKeys(change.selected_days)) !== JSON.stringify(sortedKeys(prev.selected_days))) {
    set.selected_days = change.selected_days;
  }
  if (change.repeat_interval_weeks !== undefined && change.repeat_interval_weeks !== prev.repeat_interval_weeks) {
    set.repeat_interval_weeks = change.repeat_interval_weeks;
  }
  if (change.end_condition !== undefined && JSON.stringify(change.end_condition.value) !== JSON.stringify(prev.end_condition)) {
    if (change.end_condition.value === null) clear.push("end_condition");
    else set.end_condition = change.end_condition.value;
  }
  if (change.unskip_dates !== undefined) {
    const kept = prev.exclusions.filter((d) => !change.unskip_dates!.includes(d));
    if (kept.length !== prev.exclusions.length) set.exclusions = kept;
  }
  checkSeries({
    selected_days: (set.selected_days as Record<string, string> | undefined) ?? prev.selected_days,
    end_condition: change.end_condition?.value === undefined ? prev.end_condition : change.end_condition.value,
  });
  return { set, clear };
}

const sortedKeys = (record: Record<string, string>) => Object.fromEntries(Object.entries(record).sort());

export const deleteRecurringShift = {
  definition: {
    name: "delete_recurring_shift",
    title: "Delete recurring shift",
    description:
      "Deletes an entire repeating shift series, including past occurrences. To end future shifts while keeping past ones, use save_recurring_shift with end_date instead. " +
      "Confirm with the user first.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", description: "Recurring series ID from get_overview or a shift's recurring_id." } },
      required: ["id"],
      additionalProperties: false,
    },
    annotations: { title: "Delete recurring shift", ...destructive },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["id"]);
    return { id: requiredString(args.id, "id") };
  },
} satisfies ToolSpec;

/** What update_shift or delete_shifts does to one date of a recurring series. */
export type OccurrenceChange =
  | { kind: "skip" }
  /** "" removes the note. */
  | { kind: "note"; note: string }
  /** Becomes a one-off shift. Absent fields keep the date's values. */
  | { kind: "change"; date?: string; start?: string; end?: string; note?: string; forceDetach?: boolean };

/**
 * ShiftsViewModel+Editing.convertVirtualShift: the series columns to write, and the
 * one-off shift to add when the date's day, times or job change.
 */
export function planOccurrence(
  series: { start_time: string; end_time: string; exclusions: string[]; date_specific_notes: Record<string, string> },
  dateStr: string,
  change: OccurrenceChange,
) {
  const notes = { ...series.date_specific_notes };
  const notesColumn = () => (Object.keys(notes).length === 0 ? null : notes);
  const excluded = () => [...new Set([...series.exclusions, dateStr])].sort();
  if (change.kind === "skip") return { exclusions: excluded() };

  const note = change.note?.trim();
  if (change.kind === "change") {
    const times = movedTimes({ start: series.start_time, end: series.end_time }, change.start, change.end);
    const unchanged =
      !change.forceDetach &&
      (change.date ?? dateStr) === dateStr &&
      times.start_time === clockTime(series.start_time) &&
      minutes(times.end_time) % MINUTES_PER_DAY === minutes(clockTime(series.end_time)) % MINUTES_PER_DAY;
    // The app keeps the date in the series when only its note changes.
    if (!unchanged) {
      const shiftNote = note === undefined ? notes[dateStr] : note || undefined;
      delete notes[dateStr];
      return {
        exclusions: excluded(),
        date_specific_notes: notesColumn(),
        shift: { shift_date: change.date ?? dateStr, ...times, ...(shiftNote ? { note: shiftNote } : {}) },
      };
    }
    if (note === undefined) return {};
  }
  if (note) notes[dateStr] = note;
  else delete notes[dateStr];
  return { date_specific_notes: notesColumn() };
}

// ---------- Clashes with existing shifts ----------

export type TimedShift = { date: string; start: string; end: string };

/**
 * ShiftConflictDetector.detectConflicts: the dates in `dates` where a shift from `start`
 * to `end` overlaps one of `existing`, counting the part of a night shift after midnight
 * on the next day.
 */
export function overlappingDates(dates: string[], start: string, end: string, existing: TimedShift[]): string[] {
  const busy = new Map<string, [number, number][]>();
  const add = (day: string, from: number, to: number) => busy.set(day, [...(busy.get(day) ?? []), [from, to]]);
  for (const shift of existing) {
    const s = minutes(clockTime(shift.start));
    const e = minutes(clockTime(shift.end));
    if (e > s) add(shift.date, s, e);
    else {
      add(shift.date, s, MINUTES_PER_DAY);
      add(addDays(shift.date, 1), 0, e);
    }
  }
  const s = minutes(start);
  const e = minutes(end);
  const hits = (day: string, from: number, to: number) => (busy.get(day) ?? []).some(([a, b]) => from < b && a < to);
  return dates.filter((d) => (e > s ? hits(d, s, e) : hits(d, s, MINUTES_PER_DAY) || hits(addDays(d, 1), 0, e)));
}
