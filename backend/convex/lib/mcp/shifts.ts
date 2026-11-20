import { allowOnly, type Args, optional, optionalString, requiredString, today } from "./args";
import type { ToolSpec } from "./registry";
import { addDays, parseDate, parseRange, parseTime, ToolError } from "./shiftTimes";

// The shift tools and the arguments each one accepts. Arguments are checked here, so the
// Convex functions in mcpShifts.ts get well-formed values.

const MAX_RANGE_DAYS = 93;
const MAX_NOTE_LENGTH = 500;

const date = { type: "string", format: "date", description: "YYYY-MM-DD" };
const time = { type: "string", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$", description: "HH:mm, 24-hour clock" };
const endTime = {
  type: "string",
  pattern: "^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$",
  description: "HH:mm, 24-hour clock. An end at or before the start is on the next day.",
};
const id = { type: "string", description: "An id from list_shifts or list_jobs" };
const note = { type: "string", maxLength: MAX_NOTE_LENGTH };
const revision = {
  type: "number",
  description: "The shift's revision from list_shifts. A change made since then makes the call fail; list the shifts again.",
};

const readOnly = { readOnlyHint: true, openWorldHint: false };

function requiredRevision(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new ToolError("revision is required. Get it from list_shifts.");
  return value;
}

/** A shift date within five years of today, which catches a mistyped year. */
function shiftDate(value: unknown, today: string): string {
  const date = parseDate(value, "date");
  if (date < addDays(today, -5 * 366) || date > addDays(today, 5 * 366)) {
    throw new ToolError("date must be within five years of today.");
  }
  return date;
}

function dateRange(args: Args) {
  allowOnly(args, ["from", "to"]);
  return parseRange(args.from, args.to, MAX_RANGE_DAYS);
}

export const listShifts = {
  definition: {
    name: "list_shifts",
    title: "List shifts",
    description:
      "Shifts from `from` to `to`, both included, at most 93 days. Times are the user's local clock times. " +
      "One-off shifts have a shift_id and revision for update_shift and delete_shift. " +
      "Recurring shifts come from a repeating series, with its recurring_shift_id and recurring_revision for " +
      "change_recurring_occurrence (one date) and update_recurring_shift (the whole series).",
    inputSchema: {
      type: "object",
      properties: { from: date, to: date },
      required: ["from", "to"],
      additionalProperties: false,
    },
    annotations: { title: "List shifts", ...readOnly },
  },
  scope: "read",
  parse: dateRange,
} satisfies ToolSpec;

export const getEarnings = {
  definition: {
    name: "get_earnings",
    title: "Get earnings",
    description:
      "Gross pay before tax and paid hours for the shifts dated `from` to `to`, at most 93 days, per currency. " +
      "It counts one-off and recurring shifts with supplements, breaks and weekly overtime, as the Tidex app does. " +
      "Overlapping shifts on the same date count once, as in the app, so the total can be less than the listed shifts add up to. " +
      "Payroll adjustments such as bonuses are not included.",
    inputSchema: {
      type: "object",
      properties: { from: date, to: date },
      required: ["from", "to"],
      additionalProperties: false,
    },
    annotations: { title: "Get earnings", ...readOnly },
  },
  scope: "read",
  parse: dateRange,
} satisfies ToolSpec;

export const addShift = {
  definition: {
    name: "add_shift",
    title: "Add shift",
    description:
      "Adds a one-off shift. Without job_id it goes to the default job, or the first job when none is the default. " +
      "Adding a shift that already exists with the same job, date and times returns that shift instead of a copy, " +
      "without changing its note; use update_shift for that.",
    inputSchema: {
      type: "object",
      properties: { date, start: time, end: endTime, job_id: id, note },
      required: ["date", "start", "end"],
      additionalProperties: false,
    },
    annotations: { title: "Add shift", readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["date", "start", "end", "job_id", "note"]);
    return {
      date: shiftDate(args.date, today()),
      start: parseTime(args.start, "start"),
      end: parseTime(args.end, "end", true),
      job_id: optionalString(args.job_id, "job_id"),
      note: optionalString(args.note, "note", MAX_NOTE_LENGTH),
    };
  },
} satisfies ToolSpec;

export const updateShift = {
  definition: {
    name: "update_shift",
    title: "Change shift",
    description:
      "Changes a one-off shift's date, times, job or note. Give only what changes. " +
      "A new start without a new end keeps the shift's length. An empty note removes the note.",
    inputSchema: {
      type: "object",
      properties: { shift_id: id, revision, date, start: time, end: endTime, job_id: id, note },
      required: ["shift_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Change shift", readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["shift_id", "revision", "date", "start", "end", "job_id", "note"]);
    const parsed = {
      shift_id: requiredString(args.shift_id, "shift_id"),
      revision: requiredRevision(args.revision),
      date: optional(args.date, (v) => shiftDate(v, today())),
      start: optional(args.start, (v) => parseTime(v, "start")),
      end: optional(args.end, (v) => parseTime(v, "end", true)),
      job_id: optionalString(args.job_id, "job_id"),
      note: optionalString(args.note, "note", MAX_NOTE_LENGTH),
    };
    if ([parsed.date, parsed.start, parsed.end, parsed.job_id, parsed.note].every((v) => v === undefined)) {
      throw new ToolError("Give at least one of date, start, end, job_id or note.");
    }
    return parsed;
  },
} satisfies ToolSpec;

export const deleteShift = {
  definition: {
    name: "delete_shift",
    title: "Delete shift",
    description: "Deletes a one-off shift.",
    inputSchema: {
      type: "object",
      properties: { shift_id: id, revision },
      required: ["shift_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Delete shift", readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["shift_id", "revision"]);
    return { shift_id: requiredString(args.shift_id, "shift_id"), revision: requiredRevision(args.revision) };
  },
} satisfies ToolSpec;
