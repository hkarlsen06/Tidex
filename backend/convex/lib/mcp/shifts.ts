import {
  adds,
  allowOnly,
  type Args,
  boolean,
  date,
  destructive,
  endTime,
  jobFilter,
  jobRef,
  list,
  MAX_RANGE_DAYS,
  month,
  nearDate,
  oneOf,
  optional,
  optionalString,
  parseDateQuery,
  readOnly,
  requiredString,
  time,
  updates,
} from "./args";
import type { ToolSpec } from "./registry";
import { parseShiftId, parseTime, ToolError } from "./shiftTimes";

// The schedule, earnings and shift tools. Arguments are checked here so mcpShifts.ts
// receives clean, validated inputs.

const MAX_NOTE_LENGTH = 500;
const MAX_BATCH_SHIFTS = 50;

const note = { type: "string", maxLength: MAX_NOTE_LENGTH, description: "Optional note. Pass empty string to clear." };

const shiftInputSchema = {
  type: "object",
  properties: {
    date,
    start: time,
    end: endTime,
    job: jobRef,
    note: { type: "string", maxLength: MAX_NOTE_LENGTH },
  },
  required: ["date", "start", "end"],
  additionalProperties: false,
};

function parseShiftDraft(value: unknown, index: number) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new ToolError(`shifts[${index}] must be an object with date, start and end.`);
  }
  const s = value as Args;
  allowOnly(s, ["date", "start", "end", "job", "note"]);
  return {
    date: nearDate(s.date, `shifts[${index}].date`),
    start: parseTime(s.start, `shifts[${index}].start`),
    end: parseTime(s.end, `shifts[${index}].end`, true),
    job: optionalString(s.job, `shifts[${index}].job`),
    note: optionalString(s.note, `shifts[${index}].note`, MAX_NOTE_LENGTH),
  };
}

export const getSchedule = {
  definition: {
    name: "get_schedule",
    title: "Get schedule",
    description:
      "Returns shifts (one-off and recurring occurrences), calendar events and a pay summary for a month or date range (up to 366 days). " +
      "Defaults to the next 14 days from today when month and from are omitted. " +
      "Each shift includes hours, break minutes, gross pay, net pay after tax, tax deducted, effective tax percent and payout date, " +
      "plus an id that works directly in update_shift and delete_shifts for both one-off and recurring shifts.",
    inputSchema: {
      type: "object",
      properties: {
        month,
        from: { ...date, description: "Start date (YYYY-MM-DD). Defaults to today when month is omitted." },
        to: { ...date, description: "End date (YYYY-MM-DD). Defaults to 13 days after from." },
        job: jobFilter,
        include_events: { type: "boolean", description: "Include private calendar events (default true)." },
      },
      additionalProperties: false,
    },
    annotations: { title: "Get schedule", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["month", "from", "to", "job", "include_events"]);
    return {
      ...parseDateQuery(args, MAX_RANGE_DAYS),
      job: optionalString(args.job, "job"),
      include_events: optional(args.include_events, (v) => boolean(v, "include_events")) ?? true,
    };
  },
} satisfies ToolSpec;

export const getEarnings = {
  definition: {
    name: "get_earnings",
    title: "Get earnings",
    description:
      "Calculates gross pay, net pay after tax, tax deducted, base pay, supplements, overtime, paid hours and payroll adjustments per currency and job. " +
      'Use by: "worked" (default) for shifts worked in a month or date range (up to 366 days). ' +
      'Use by: "payout" with month (YYYY-MM) for the exact paycheck paid out in that month based on each job\'s pay period, half-tax month and adjustments. ' +
      "Defaults to the current month when month and from are omitted.",
    inputSchema: {
      type: "object",
      properties: {
        month,
        from: { ...date, description: 'Start date (YYYY-MM-DD), for by: "worked".' },
        to: { ...date, description: 'End date (YYYY-MM-DD), for by: "worked".' },
        by: {
          type: "string",
          enum: ["worked", "payout"],
          description: '"worked" (default): shifts worked in the range. "payout": paychecks paid out in the given month.',
        },
        job: jobFilter,
      },
      additionalProperties: false,
    },
    annotations: { title: "Get earnings", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["month", "from", "to", "by", "job"]);
    const by = optional(args.by, (v) => oneOf(v, "by", ["worked", "payout"] as const)) ?? "worked";
    const range = parseDateQuery(args, MAX_RANGE_DAYS);
    if (by === "payout" && (range.from !== undefined || range.to !== undefined)) {
      throw new ToolError('Use month (YYYY-MM) instead of from/to when by is "payout".');
    }
    return {
      by,
      ...range,
      job: optionalString(args.job, "job"),
    };
  },
} satisfies ToolSpec;

export const addShifts = {
  definition: {
    name: "add_shifts",
    title: "Add shifts",
    description:
      "Adds 1 to 50 one-off shifts in one call. Omit job to use the default job, or pass a job ID or name. " +
      "If a shift with the same job, date and times already exists, it is returned without creating a duplicate.",
    inputSchema: {
      type: "object",
      properties: {
        shifts: {
          type: "array",
          items: shiftInputSchema,
          minItems: 1,
          maxItems: MAX_BATCH_SHIFTS,
          description: "List of shifts to add.",
        },
      },
      required: ["shifts"],
      additionalProperties: false,
    },
    annotations: { title: "Add shifts", ...adds },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["shifts"]);
    const items = list(args.shifts, "shifts", MAX_BATCH_SHIFTS);
    if (items.length === 0) throw new ToolError("shifts needs at least one shift.");
    return { shifts: items.map((item, i) => parseShiftDraft(item, i)) };
  },
} satisfies ToolSpec;

export const updateShift = {
  definition: {
    name: "update_shift",
    title: "Update shift",
    description:
      "Updates a shift by its id from get_schedule. Works for both one-off shifts and individual recurring shift occurrences. " +
      "Pass only the fields to change. Changing start without end keeps the shift length. " +
      "For a recurring occurrence, changing only note updates that date's note on the series; changing date, times or job converts that date into a one-off shift.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Shift id from get_schedule (one-off UUID or recurring:<id>:<date>)." },
        date,
        start: time,
        end: endTime,
        job: jobRef,
        note,
      },
      required: ["id"],
      additionalProperties: false,
    },
    annotations: { title: "Update shift", ...updates },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["id", "date", "start", "end", "job", "note"]);
    const id = requiredString(args.id, "id");
    parseShiftId(id);
    const parsed = {
      id,
      date: optional(args.date, (v) => nearDate(v, "date")),
      start: optional(args.start, (v) => parseTime(v, "start")),
      end: optional(args.end, (v) => parseTime(v, "end", true)),
      job: optionalString(args.job, "job"),
      note: optionalString(args.note, "note", MAX_NOTE_LENGTH),
    };
    if ([parsed.date, parsed.start, parsed.end, parsed.job, parsed.note].every((v) => v === undefined)) {
      throw new ToolError("Give at least one of date, start, end, job or note.");
    }
    return parsed;
  },
} satisfies ToolSpec;

export const deleteShifts = {
  definition: {
    name: "delete_shifts",
    title: "Delete shifts",
    description:
      "Deletes 1 to 50 shifts by their ids from get_schedule. Works for both one-off shifts (deletes them) and recurring shift occurrences (skips those dates on the series). " +
      "Confirm with the user first.",
    inputSchema: {
      type: "object",
      properties: {
        ids: {
          type: "array",
          items: { type: "string" },
          minItems: 1,
          maxItems: MAX_BATCH_SHIFTS,
          description: "Shift ids from get_schedule.",
        },
      },
      required: ["ids"],
      additionalProperties: false,
    },
    annotations: { title: "Delete shifts", ...destructive },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["ids"]);
    const items = list(args.ids, "ids", MAX_BATCH_SHIFTS);
    if (items.length === 0) throw new ToolError("ids needs at least one shift id.");
    const ids = [...new Set(items.map((v, i) => requiredString(v, `ids[${i}]`)))];
    for (const id of ids) parseShiftId(id);
    return { ids };
  },
} satisfies ToolSpec;
