import { generateVirtualShiftsForMonth, resolveEndWindow, toISODate } from "../shared/recurring/utils";
import {
  adds,
  allowOnly,
  type Args,
  boolean,
  changes,
  date,
  endTime,
  integer,
  jobId,
  list,
  nearDate,
  optional,
  optionalString,
  readOnly,
  requiredRevision,
  requiredString,
  revision,
  time,
} from "./args";
import type { ToolSpec } from "./registry";
import { addDays, clockTime, MINUTES_PER_DAY, minutes, movedTimes, parseDate, parseTime, shiftTimes, ToolError } from "./shiftTimes";

// The recurring shift tools, the arguments each one accepts, and the series columns they
// write. The server checks little inside the JSON columns, and one row the app can't
// decode stops its sync of recurring_shifts, so every value is built here the way the app
// builds it.

export const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

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
    for (const shift of generateVirtualShiftsForMonth({ year, month: m }, draft)) {
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

export const firstDate = (series: Pick<Series, "selected_days">) => Object.values(series.selected_days).sort()[0];

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

/**
 * Recurring rows store a midnight end as 00:00: the server's timetz column rejects 24:00.
 * An end at or before the start is on the next day either way.
 */
export function recurringTimes(start: string, end: string) {
  const times = shiftTimes(start, end);
  return { start_time: times.start_time, end_time: midnightAsZero(times.end_time) };
}

const midnightAsZero = (end: string) => (end === "24:00" ? "00:00" : end);

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

function parseEnds(value: unknown): EndCondition | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new ToolError("ends must be an object with a type.");
  const ends = value as Args;
  switch (ends.type) {
    case "never":
      allowOnly(ends, ["type"]);
      return null;
    case "months":
      allowOnly(ends, ["type", "value"]);
      return { type: "months", value: integer(ends.value, "ends.value", 1, 24) };
    case "years":
      allowOnly(ends, ["type", "value"]);
      return { type: "years", value: integer(ends.value, "ends.value", 1, 5) };
    case "end_date":
      allowOnly(ends, ["type", "date"]);
      return { type: "end_date", date: nearDate(ends.date, "ends.date") };
    default:
      throw new ToolError("ends.type must be never, months, years or end_date.");
  }
}

/** A series that has at least its first date. */
export function checkSeries(series: Pick<Series, "selected_days" | "end_condition">) {
  const last = lastDate(series);
  if (last !== null && last < firstDate(series)) {
    throw new ToolError("The series would end before its first date. Delete it with delete_recurring_shift instead.");
  }
}

const everyWeeks = (value: unknown) => integer(value, "every_weeks", 1, 9) - 1;

const recurringId = { type: "string", description: "A recurring_shift_id from list_recurring_shifts or list_shifts" };
const recurringRevision = revision("list_recurring_shifts or list_shifts (recurring_revision)");
const firstDates = {
  type: "array",
  items: date,
  minItems: 1,
  maxItems: 7,
  description: "The first shift on each weekday the series repeats on, one date per weekday. Every repeat counts from these dates.",
};
const every = { type: "integer", minimum: 1, maximum: 9, description: "1 is every week, 2 every second week, up to 9." };
const ends = {
  type: "object",
  description:
    'When the series stops. {"type": "never"}, {"type": "months", "value": 1-24} or {"type": "years", "value": 1-5} ' +
    'counted from the earliest first date, or {"type": "end_date", "date": "YYYY-MM-DD"} with that date included.',
  properties: {
    type: { type: "string", enum: ["never", "months", "years", "end_date"] },
    value: { type: "integer", minimum: 1, maximum: 24 },
    date,
  },
  required: ["type"],
  additionalProperties: false,
};

export const listRecurringShifts = {
  definition: {
    name: "list_recurring_shifts",
    title: "List recurring shifts",
    description:
      "The user's repeating shift series: times, weekdays, how often and until when they repeat, skipped dates and per-date notes. " +
      "list_shifts shows the dates each series puts in a range.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { title: "List recurring shifts", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, []);
    return {};
  },
} satisfies ToolSpec;

export const addRecurringShift = {
  definition: {
    name: "add_recurring_shift",
    title: "Add recurring shift",
    description:
      "Adds a series of shifts that repeats on the weekdays of first_dates. Without job_id it goes to the default job. " +
      "As in the Tidex app, dates where the user already has a shift that overlaps are skipped; the result lists them. " +
      "Adding the same series again returns the existing one.",
    inputSchema: {
      type: "object",
      properties: { first_dates: firstDates, start: time, end: endTime, every_weeks: every, ends, job_id: jobId },
      required: ["first_dates", "start", "end"],
      additionalProperties: false,
    },
    annotations: { title: "Add recurring shift", ...adds },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["first_dates", "start", "end", "every_weeks", "ends", "job_id"]);
    const series = {
      selected_days: parseFirstDates(args.first_dates),
      ...recurringTimes(parseTime(args.start, "start"), parseTime(args.end, "end", true)),
      repeat_interval_weeks: optional(args.every_weeks, everyWeeks) ?? 0,
      end_condition: optional(args.ends, parseEnds) ?? null,
    };
    checkSeries(series);
    return { ...series, job_id: optionalString(args.job_id, "job_id") };
  },
} satisfies ToolSpec;

export const updateRecurringShift = {
  definition: {
    name: "update_recurring_shift",
    title: "Change recurring shift",
    description:
      "Changes a whole series: times, weekdays, how often it repeats, when it ends, or its job. Give only what changes. " +
      "A new start without a new end keeps the shift's length. first_dates replaces all weekdays. " +
      "unskip_dates puts skipped dates back. To change a single date use change_recurring_occurrence.",
    inputSchema: {
      type: "object",
      properties: {
        recurring_shift_id: recurringId,
        revision: recurringRevision,
        first_dates: firstDates,
        start: time,
        end: endTime,
        every_weeks: every,
        ends,
        job_id: jobId,
        unskip_dates: { type: "array", items: date, maxItems: 100, description: "Skipped dates to put back in the series" },
      },
      required: ["recurring_shift_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Change recurring shift", ...changes },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["recurring_shift_id", "revision", "first_dates", "start", "end", "every_weeks", "ends", "job_id", "unskip_dates"]);
    const parsed = {
      recurring_shift_id: requiredString(args.recurring_shift_id, "recurring_shift_id"),
      revision: requiredRevision(args.revision, "list_recurring_shifts"),
      selected_days: optional(args.first_dates, parseFirstDates),
      start: optional(args.start, (v) => parseTime(v, "start")),
      end: optional(args.end, (v) => parseTime(v, "end", true)),
      repeat_interval_weeks: optional(args.every_weeks, everyWeeks),
      // Absent leaves the end alone; {type: "never"} removes it.
      end_condition: args.ends === undefined || args.ends === null ? undefined : { value: parseEnds(args.ends) },
      job_id: optionalString(args.job_id, "job_id"),
      unskip_dates: optional(args.unskip_dates, (v) => list(v, "unskip_dates", 100).map((d) => parseDate(d, "unskip_dates"))),
    };
    const { recurring_shift_id, revision, ...change } = parsed;
    if (Object.values(change).every((v) => v === undefined)) {
      throw new ToolError("Give at least one of first_dates, start, end, every_weeks, ends, job_id or unskip_dates.");
    }
    return parsed;
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
    const end = midnightAsZero(moved.end_time);
    if (end !== midnightAsZero(clockTime(prev.end_time))) set.end_time = end;
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

export const stopRecurringShift = {
  definition: {
    name: "stop_recurring_shift",
    title: "Stop recurring shift",
    description:
      "Ends a series after last_date, which keeps its last shift. Earlier shifts stay. It can't make a series run longer; use update_recurring_shift for that.",
    inputSchema: {
      type: "object",
      properties: { recurring_shift_id: recurringId, revision: recurringRevision, last_date: date },
      required: ["recurring_shift_id", "revision", "last_date"],
      additionalProperties: false,
    },
    annotations: { title: "Stop recurring shift", ...changes },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["recurring_shift_id", "revision", "last_date"]);
    return {
      recurring_shift_id: requiredString(args.recurring_shift_id, "recurring_shift_id"),
      revision: requiredRevision(args.revision, "list_recurring_shifts"),
      last_date: nearDate(args.last_date, "last_date"),
    };
  },
} satisfies ToolSpec;

/** The end_condition that stops `series` after `last`, refusing one that would lengthen it. */
export function stoppedEnd(series: Pick<Series, "selected_days" | "end_condition">, last: string): EndCondition {
  const current = lastDate(series);
  if (current !== null && current <= last) throw new ToolError(`The series already ends on ${current}.`);
  const end: EndCondition = { type: "end_date", date: last };
  checkSeries({ selected_days: series.selected_days, end_condition: end });
  return end;
}

export const deleteRecurringShift = {
  definition: {
    name: "delete_recurring_shift",
    title: "Delete recurring shift",
    description:
      "Deletes a whole series, past dates included. One-off shifts made from its dates stay. To end it from a date and keep earlier shifts, use stop_recurring_shift.",
    inputSchema: {
      type: "object",
      properties: { recurring_shift_id: recurringId, revision: recurringRevision },
      required: ["recurring_shift_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Delete recurring shift", ...changes },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["recurring_shift_id", "revision"]);
    return {
      recurring_shift_id: requiredString(args.recurring_shift_id, "recurring_shift_id"),
      revision: requiredRevision(args.revision, "list_recurring_shifts"),
    };
  },
} satisfies ToolSpec;

const MAX_NOTE_LENGTH = 500;

/** What change_recurring_occurrence does to one date of a series. */
export type OccurrenceChange =
  | { kind: "skip" }
  /** "" removes the note. */
  | { kind: "note"; note: string }
  /** Becomes a one-off shift. Absent fields keep the date's values. */
  | { kind: "change"; date?: string; start?: string; end?: string; note?: string };

export const changeRecurringOccurrence = {
  definition: {
    name: "change_recurring_occurrence",
    title: "Change one date of a recurring shift",
    description:
      "Changes one date of a series, as the Tidex app does. skip: true removes that date only. " +
      "A note alone sets that date's note (an empty note removes it). " +
      "A new_date, start or end takes the date out of the series and adds a one-off shift with the changes on the series' job; " +
      "a new start without a new end keeps the shift's length, and the date's note moves to the new shift unless note is given.",
    inputSchema: {
      type: "object",
      properties: {
        recurring_shift_id: recurringId,
        revision: recurringRevision,
        date: { ...date, description: "The date to change, as list_shifts shows it" },
        skip: { type: "boolean", description: "true removes this date from the series" },
        new_date: date,
        start: time,
        end: endTime,
        note: { type: "string", maxLength: MAX_NOTE_LENGTH },
      },
      required: ["recurring_shift_id", "revision", "date"],
      additionalProperties: false,
    },
    annotations: { title: "Change one date of a recurring shift", ...changes },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["recurring_shift_id", "revision", "date", "skip", "new_date", "start", "end", "note"]);
    const target = {
      recurring_shift_id: requiredString(args.recurring_shift_id, "recurring_shift_id"),
      revision: requiredRevision(args.revision, "list_recurring_shifts"),
      date: parseDate(args.date, "date"),
    };
    const note = optionalString(args.note, "note", MAX_NOTE_LENGTH);
    const moved = {
      date: optional(args.new_date, (v) => nearDate(v, "new_date")),
      start: optional(args.start, (v) => parseTime(v, "start")),
      end: optional(args.end, (v) => parseTime(v, "end", true)),
    };
    const moves = Object.values(moved).some((v) => v !== undefined);
    if (optional(args.skip, (v) => boolean(v, "skip")) === true) {
      if (moves || note !== undefined) throw new ToolError("skip can't be combined with other changes.");
      return { ...target, change: { kind: "skip" } as OccurrenceChange };
    }
    if (moves) return { ...target, change: { kind: "change", ...moved, note } as OccurrenceChange };
    if (note !== undefined) return { ...target, change: { kind: "note", note } as OccurrenceChange };
    throw new ToolError("Give skip: true, a note, or at least one of new_date, start or end.");
  },
} satisfies ToolSpec;

/**
 * ShiftsViewModel+Editing.convertVirtualShift: the series columns to write, and the
 * one-off shift to add when the date's day or times change.
 */
export function planOccurrence(
  series: { start_time: string; end_time: string; exclusions: string[]; date_specific_notes: Record<string, string> },
  date: string,
  change: OccurrenceChange,
) {
  const notes = { ...series.date_specific_notes };
  const notesColumn = () => (Object.keys(notes).length === 0 ? null : notes);
  const excluded = () => [...new Set([...series.exclusions, date])].sort();
  if (change.kind === "skip") return { exclusions: excluded() };

  const note = change.note?.trim();
  if (change.kind === "change") {
    const times = movedTimes({ start: series.start_time, end: series.end_time }, change.start, change.end);
    const unchanged =
      (change.date ?? date) === date &&
      times.start_time === clockTime(series.start_time) &&
      minutes(times.end_time) % MINUTES_PER_DAY === minutes(clockTime(series.end_time)) % MINUTES_PER_DAY;
    // The app keeps the date in the series when only its note changes.
    if (!unchanged) {
      const shiftNote = note === undefined ? notes[date] : note || undefined;
      delete notes[date];
      return {
        exclusions: excluded(),
        date_specific_notes: notesColumn(),
        shift: { shift_date: change.date ?? date, ...times, ...(shiftNote ? { note: shiftNote } : {}) },
      };
    }
    if (note === undefined) return {};
  }
  if (note) notes[date] = note;
  else delete notes[date];
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
