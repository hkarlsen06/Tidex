import { isScheduleTimeZone } from "../scheduleTimeZone";
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
  oneOf,
  optional,
  optionalString,
  readOnly,
  requiredRevision,
  requiredString,
  revision,
  text,
  time,
} from "./args";
import type { ToolSpec } from "./registry";
import { addDays, MINUTES_PER_DAY, minutes, parseRange, parseTime, ToolError } from "./shiftTimes";

// The tools for events, payroll adjustments and settings, the arguments each one accepts,
// and the rows they write. The server checks little inside the JSON columns, and one row
// the app can't decode stops its sync of that table, so every row is built here the way
// the app builds it. Recurring shifts are in recurring.ts.

const MAX_LIST_DAYS = 366;
const MAX_REMINDERS = 4;
/** The app's reminder picker goes up to 48 hours and 59 minutes. */
const MAX_REMINDER_MINUTES = 48 * 60 + 59;

/** Distinct reminder offsets, largest first, as the app stores them. */
function reminderList(value: unknown, field: string, parse: (item: unknown) => number): number[] {
  const parsed = list(value, field, MAX_REMINDERS).map(parse);
  if (new Set(parsed).size !== parsed.length) throw new ToolError(`${field} has the same reminder twice.`);
  return parsed.sort((a, b) => b - a);
}

const reminderMinutes = (value: unknown, field: string) =>
  reminderList(value, field, (m) => integer(m, field, 1, MAX_REMINDER_MINUTES));

const rangeSchema = (what: string) => ({
  type: "object" as const,
  properties: { from: { ...date, description: `First ${what} date, YYYY-MM-DD` }, to: { ...date, description: `Last ${what} date, YYYY-MM-DD` } },
  required: ["from", "to"],
  additionalProperties: false as const,
});

function listRange(args: Args) {
  allowOnly(args, ["from", "to"]);
  return parseRange(args.from, args.to, MAX_LIST_DAYS);
}

// ---------- Events ----------

/** The events columns the app writes. */
export type EventFields = {
  start_date: string;
  end_date: string;
  is_all_day: boolean;
  start_time?: string;
  end_time?: string;
  note: string;
  notification_minutes_array?: number[];
  notification_anchor_time?: string;
};

/** An event as the tools describe it. A timed event has start and end; an all-day one has neither. */
export type EventDraft = {
  note: string;
  date: string;
  end_date?: string;
  start?: string;
  end?: string;
  reminder_minutes?: number[];
  reminder_days_before?: number[];
  reminder_time?: string;
};

const MAX_EVENT_NOTE = 1000;

/** The row the app writes for `draft`, after the app's and the server's checks. */
export function eventFields(draft: EventDraft): EventFields {
  const note = draft.note.trim();
  if (note === "") throw new ToolError("note can't be blank.");
  if ((draft.start === undefined) !== (draft.end === undefined)) {
    throw new ToolError("A timed event needs both start and end; an all-day event has neither.");
  }
  if (draft.start !== undefined && draft.end !== undefined) {
    if (draft.end_date !== undefined && draft.end_date !== draft.date) throw new ToolError("A timed event is on one date. Leave out end_date.");
    if (minutes(draft.end) <= minutes(draft.start)) throw new ToolError("end must be after start on the same day. Timed events can't run past midnight.");
    if (draft.reminder_days_before !== undefined || draft.reminder_time !== undefined) {
      throw new ToolError("A timed event takes reminder_minutes, not reminder_days_before or reminder_time.");
    }
    const reminders = draft.reminder_minutes ?? [];
    return {
      start_date: draft.date,
      end_date: draft.date,
      is_all_day: false,
      start_time: draft.start,
      end_time: draft.end,
      note,
      ...(reminders.length > 0 ? { notification_minutes_array: reminders } : {}),
    };
  }
  const endDate = draft.end_date ?? draft.date;
  if (endDate < draft.date) throw new ToolError("end_date can't be before date.");
  if (draft.reminder_minutes !== undefined) {
    throw new ToolError("An all-day event takes reminder_days_before and reminder_time, not reminder_minutes.");
  }
  const days = draft.reminder_days_before ?? [];
  if (days.length > 0 && draft.reminder_time === undefined) {
    throw new ToolError("reminder_time is required with reminder_days_before: the clock time the reminders go off.");
  }
  return {
    start_date: draft.date,
    end_date: endDate,
    is_all_day: true,
    note,
    ...(days.length > 0 ? { notification_minutes_array: days.map((d) => d * MINUTES_PER_DAY), notification_anchor_time: draft.reminder_time } : {}),
  };
}

/** The event `prev` with `change` applied. Reminders stay only while the event stays timed or all-day. */
export function changedEvent(prev: EventFields, change: Partial<EventDraft> & { all_day?: boolean }): EventDraft {
  const timed = change.start !== undefined || change.end !== undefined;
  if (timed && change.all_day === true) throw new ToolError("all_day: true can't be combined with start or end.");
  const allDay = change.all_day === true || (!timed && change.all_day !== false && prev.is_all_day);
  if (!allDay && !timed && prev.is_all_day) throw new ToolError("Give start and end to make an all-day event timed.");
  const date = change.date ?? prev.start_date;
  const keepsKind = allDay === prev.is_all_day;
  const stored = prev.notification_minutes_array ?? [];
  if (allDay) {
    const length = keepsKind ? Math.round((Date.parse(prev.end_date) - Date.parse(prev.start_date)) / 86_400_000) : 0;
    return {
      note: change.note ?? prev.note,
      date,
      end_date: change.end_date ?? addDays(date, length),
      reminder_days_before: change.reminder_days_before ?? (keepsKind ? stored.map((m) => m / MINUTES_PER_DAY) : undefined),
      reminder_time: change.reminder_time ?? (keepsKind ? prev.notification_anchor_time : undefined),
      reminder_minutes: change.reminder_minutes,
    };
  }
  return {
    note: change.note ?? prev.note,
    date,
    end_date: change.end_date,
    start: change.start ?? prev.start_time,
    end: change.end ?? prev.end_time,
    reminder_minutes: change.reminder_minutes ?? (keepsKind ? stored : undefined),
    reminder_time: change.reminder_time,
    reminder_days_before: change.reminder_days_before,
  };
}

const eventId = { type: "string", description: "An event_id from list_events" };
const eventProperties = {
  note: { type: "string", maxLength: MAX_EVENT_NOTE, description: "What the event is. Required, not blank." },
  date: { ...date, description: "The event's date, or an all-day event's first date" },
  end_date: { ...date, description: "An all-day event's last date. Leave out for one day." },
  start: time,
  end: { ...endTime, description: "HH:mm, after start on the same day. 24:00 is midnight." },
  reminder_minutes: {
    type: "array",
    items: { type: "integer", minimum: 1, maximum: MAX_REMINDER_MINUTES },
    maxItems: MAX_REMINDERS,
    description: "Timed events: reminders this many minutes before start. An empty list removes them.",
  },
  reminder_days_before: {
    type: "array",
    items: { type: "integer", minimum: 0, maximum: 2 },
    maxItems: 3,
    description: "All-day events: reminders on the day (0), the day before (1) or two days before (2). An empty list removes them.",
  },
  reminder_time: { ...time, description: "All-day events: the clock time reminders go off. Required with reminder_days_before." },
};
const reminderNote =
  "Reminders are notifications on the user's phone. The app schedules them the next time it syncs, so they need the app opened once.";

function parseEventDraft(args: Args): Partial<EventDraft> {
  return {
    note: optional(args.note, (v) => text(v, "note", MAX_EVENT_NOTE)),
    date: optional(args.date, (v) => nearDate(v, "date")),
    end_date: optional(args.end_date, (v) => nearDate(v, "end_date")),
    start: optional(args.start, (v) => parseTime(v, "start")),
    end: optional(args.end, (v) => parseTime(v, "end", true)),
    reminder_minutes: optional(args.reminder_minutes, (v) => reminderMinutes(v, "reminder_minutes")),
    reminder_days_before: optional(args.reminder_days_before, (v) =>
      reminderList(v, "reminder_days_before", (d) => integer(d, "reminder_days_before", 0, 2)),
    ),
    reminder_time: optional(args.reminder_time, (v) => parseTime(v, "reminder_time")),
  };
}

export const listEvents = {
  definition: {
    name: "list_events",
    title: "List events",
    description:
      "The user's private calendar events (not shifts) that fall on any date from `from` to `to`, at most 366 days, with their reminders.",
    inputSchema: rangeSchema("event"),
    annotations: { title: "List events", ...readOnly },
  },
  scope: "read",
  parse: listRange,
} satisfies ToolSpec;

export const addEvent = {
  definition: {
    name: "add_event",
    title: "Add event",
    description:
      "Adds a private calendar event. With start and end it is timed on one date; without them it is all-day and may span to end_date. " +
      `${reminderNote} Adding the same event again returns the existing one.`,
    inputSchema: { type: "object", properties: eventProperties, required: ["note", "date"], additionalProperties: false },
    annotations: { title: "Add event", ...adds },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, Object.keys(eventProperties));
    const draft = parseEventDraft(args);
    if (draft.note === undefined) throw new ToolError("note is required.");
    if (draft.date === undefined) throw new ToolError("date is required.");
    return eventFields(draft as EventDraft);
  },
} satisfies ToolSpec;

export const updateEvent = {
  definition: {
    name: "update_event",
    title: "Change event",
    description:
      "Changes an event. Give only what changes. start and end make it timed; all_day: true makes it all-day. " +
      "Moving an all-day event's date keeps its length. Reminders stay unless it changes between timed and all-day. " +
      reminderNote,
    inputSchema: {
      type: "object",
      properties: {
        event_id: eventId,
        revision: revision("list_events"),
        ...eventProperties,
        all_day: { type: "boolean", description: "true makes the event all-day" },
      },
      required: ["event_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Change event", ...changes },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["event_id", "revision", "all_day", ...Object.keys(eventProperties)]);
    const change = { ...parseEventDraft(args), all_day: optional(args.all_day, (v) => boolean(v, "all_day")) };
    if (Object.values(change).every((v) => v === undefined)) throw new ToolError("Give at least one thing to change.");
    return { event_id: requiredString(args.event_id, "event_id"), revision: requiredRevision(args.revision, "list_events"), change };
  },
} satisfies ToolSpec;

export const deleteEvent = {
  definition: {
    name: "delete_event",
    title: "Delete event",
    description: "Deletes an event and, once the app syncs, its reminders.",
    inputSchema: {
      type: "object",
      properties: { event_id: eventId, revision: revision("list_events") },
      required: ["event_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Delete event", ...changes },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["event_id", "revision"]);
    return { event_id: requiredString(args.event_id, "event_id"), revision: requiredRevision(args.revision, "list_events") };
  },
} satisfies ToolSpec;

// ---------- Payroll adjustments ----------

export const ADJUSTMENT_CATEGORIES = ["retro_pay", "bonus", "correction"] as const;
export const TAX_TREATMENTS = ["gross_taxable", "net_manual"] as const;
const MAX_DESCRIPTION = 240;
const MAX_ADJUSTMENT_NOTE = 1000;

/** An adjustment as the tools take it. */
export type AdjustmentDraft = {
  amount: number;
  description: string;
  note?: string;
  category: string;
  tax_treatment?: string;
  earned_from?: string;
  earned_to?: string;
  payout_date: string;
};

/**
 * The payroll_adjustments columns PayrollDetailsSheet writes: the job's currency, and
 * net_manual whenever the job's pay has no tax.
 */
export function adjustmentFields(draft: AdjustmentDraft, job: { id: string; currency: string; taxEnabled: boolean }) {
  if (!Number.isFinite(draft.amount) || draft.amount === 0) throw new ToolError("amount must be a number other than 0.");
  if ((draft.earned_from === undefined) !== (draft.earned_to === undefined)) {
    throw new ToolError("Give both earned_from and earned_to, or neither.");
  }
  if (draft.earned_from !== undefined && draft.earned_to !== undefined && draft.earned_from > draft.earned_to) {
    throw new ToolError("earned_from can't be after earned_to.");
  }
  const note = draft.note?.trim();
  return {
    job_id: job.id,
    amount: draft.amount,
    currency: job.currency,
    category: draft.category,
    tax_treatment: job.taxEnabled ? (draft.tax_treatment ?? "gross_taxable") : "net_manual",
    description: draft.description.trim(),
    ...(note ? { note } : {}),
    ...(draft.earned_from !== undefined ? { earned_from_date: draft.earned_from, earned_to_date: draft.earned_to } : {}),
    payout_date: draft.payout_date,
  };
}

const adjustmentId = { type: "string", description: "An adjustment_id from list_payroll_adjustments" };
const adjustmentProperties = {
  job_id: { ...jobId, description: "A job_id from list_jobs. Without it, the default job." },
  amount: { type: "number", description: "In the job's currency. Negative for a deduction. Not 0." },
  description: { type: "string", maxLength: MAX_DESCRIPTION, description: "A short label, such as Christmas bonus" },
  category: { type: "string", enum: ADJUSTMENT_CATEGORIES, description: "Default correction" },
  tax_treatment: {
    type: "string",
    enum: TAX_TREATMENTS,
    description: "gross_taxable (default) is taxed like pay; net_manual is paid out as is. Always net_manual when the job's pay has no tax.",
  },
  payout_date: { ...date, description: "The payday it is paid on" },
  earned_from: { ...date, description: "First date of the work it pays for. Give with earned_to; empty text on both removes them." },
  earned_to: { ...date, description: "Last date of the work it pays for" },
  note: { type: "string", maxLength: MAX_ADJUSTMENT_NOTE, description: "An empty note removes the note." },
};

const parseAmount = (v: unknown) => {
  if (typeof v !== "number" || !Number.isFinite(v) || v === 0) throw new ToolError("amount must be a number other than 0.");
  return v;
};
/** A date, or "" to remove it. */
const dateOrBlank = (field: string) => (v: unknown) => (v === "" ? "" : nearDate(v, field));

function parseAdjustment(args: Args) {
  return {
    job_id: optionalString(args.job_id, "job_id"),
    amount: optional(args.amount, parseAmount),
    description: optional(args.description, (v) => text(v, "description", MAX_DESCRIPTION)),
    category: optional(args.category, (v) => oneOf(v, "category", ADJUSTMENT_CATEGORIES)),
    tax_treatment: optional(args.tax_treatment, (v) => oneOf(v, "tax_treatment", TAX_TREATMENTS)),
    payout_date: optional(args.payout_date, (v) => nearDate(v, "payout_date")),
    earned_from: optional(args.earned_from, dateOrBlank("earned_from")),
    earned_to: optional(args.earned_to, dateOrBlank("earned_to")),
    note: optionalString(args.note, "note", MAX_ADJUSTMENT_NOTE),
  };
}

export const listPayrollAdjustments = {
  definition: {
    name: "list_payroll_adjustments",
    title: "List payroll adjustments",
    description:
      "Bonuses, back pay and corrections the user added to their payslips, paid out from `from` to `to`, at most 366 days. " +
      "get_earnings does not include them.",
    inputSchema: rangeSchema("payout"),
    annotations: { title: "List payroll adjustments", ...readOnly },
  },
  scope: "read",
  parse: listRange,
} satisfies ToolSpec;

export const addPayrollAdjustment = {
  definition: {
    name: "add_payroll_adjustment",
    title: "Add payroll adjustment",
    description:
      "Adds a bonus, back pay or correction to a payday, in the job's currency. The job needs its pay set up. " +
      "Adding the same adjustment again returns the existing one.",
    inputSchema: {
      type: "object",
      properties: adjustmentProperties,
      required: ["amount", "description", "payout_date"],
      additionalProperties: false,
    },
    annotations: { title: "Add payroll adjustment", ...adds },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, Object.keys(adjustmentProperties));
    const { earned_from, earned_to, ...parsed } = parseAdjustment(args);
    if (parsed.amount === undefined) throw new ToolError("amount is required.");
    if (parsed.description === undefined) throw new ToolError("description is required.");
    if (parsed.payout_date === undefined) throw new ToolError("payout_date is required.");
    const draft = {
      ...parsed,
      amount: parsed.amount,
      description: parsed.description,
      payout_date: parsed.payout_date,
      category: parsed.category ?? "correction",
      earned_from: earned_from || undefined,
      earned_to: earned_to || undefined,
    };
    // Checks the draft now; the job's currency and tax come in the mutation.
    adjustmentFields(draft, { id: "", currency: "", taxEnabled: true });
    return draft;
  },
} satisfies ToolSpec;

export const updatePayrollAdjustment = {
  definition: {
    name: "update_payroll_adjustment",
    title: "Change payroll adjustment",
    description:
      "Changes a payroll adjustment. Give only what changes. A new job_id also takes that job's currency and tax.",
    inputSchema: {
      type: "object",
      properties: { adjustment_id: adjustmentId, revision: revision("list_payroll_adjustments"), ...adjustmentProperties },
      required: ["adjustment_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Change payroll adjustment", ...changes },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["adjustment_id", "revision", ...Object.keys(adjustmentProperties)]);
    const change = parseAdjustment(args);
    if (Object.values(change).every((v) => v === undefined)) throw new ToolError("Give at least one thing to change.");
    return {
      adjustment_id: requiredString(args.adjustment_id, "adjustment_id"),
      revision: requiredRevision(args.revision, "list_payroll_adjustments"),
      change,
    };
  },
} satisfies ToolSpec;

export const deletePayrollAdjustment = {
  definition: {
    name: "delete_payroll_adjustment",
    title: "Delete payroll adjustment",
    description: "Deletes a payroll adjustment.",
    inputSchema: {
      type: "object",
      properties: { adjustment_id: adjustmentId, revision: revision("list_payroll_adjustments") },
      required: ["adjustment_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Delete payroll adjustment", ...changes },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["adjustment_id", "revision"]);
    return {
      adjustment_id: requiredString(args.adjustment_id, "adjustment_id"),
      revision: requiredRevision(args.revision, "list_payroll_adjustments"),
    };
  },
} satisfies ToolSpec;

// ---------- Settings ----------

export const THEMES = ["system", "light", "dark"] as const;
export const CALENDAR_COLORS = ["workplace", "monochrome"] as const;
export const STARTUP_TABS = ["home", "shifts", "stats", "sharing"] as const;

/** A settings change, split by where each setting is stored. */
export type SettingsChange = {
  user_settings: Partial<{
    theme: (typeof THEMES)[number];
    calendar_content_color_style: (typeof CALENDAR_COLORS)[number];
    show_dashboard_clock_buttons: boolean;
    default_startup_tab: (typeof STARTUP_TABS)[number];
  }>;
  schedule_time_zone?: string;
};

const settingsProperties = {
  theme: { type: "string", enum: THEMES },
  calendar_content_color_style: {
    type: "string",
    enum: CALENDAR_COLORS,
    description: "workplace colors calendar entries by job; monochrome uses one color",
  },
  show_dashboard_clock_buttons: { type: "boolean", description: "Clock in and out buttons on the home screen" },
  default_startup_tab: { type: "string", enum: STARTUP_TABS, description: "The tab the app opens on" },
  schedule_time_zone: {
    type: "string",
    description: "The IANA time zone the user's shift times are in, such as Europe/Oslo",
  },
};

export const getSettings = {
  definition: {
    name: "get_settings",
    title: "Get settings",
    description:
      "The user's app settings and schedule time zone, plus their notification settings as last saved from the phone. " +
      "Notification settings can only be changed in the Tidex app.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { title: "Get settings", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, []);
    return {};
  },
} satisfies ToolSpec;

export const updateSettings = {
  definition: {
    name: "update_settings",
    title: "Change settings",
    description:
      "Changes app settings. Give only what changes. Changing schedule_time_zone changes which instant every shift time " +
      "means. Notification settings live on the user's phone and can only be changed in the Tidex app.",
    inputSchema: { type: "object", properties: settingsProperties, additionalProperties: false },
    annotations: { title: "Change settings", readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  scope: "write",
  parse: (args): SettingsChange => {
    allowOnly(args, Object.keys(settingsProperties));
    const settings = {
      theme: optional(args.theme, (v) => oneOf(v, "theme", THEMES)),
      calendar_content_color_style: optional(args.calendar_content_color_style, (v) =>
        oneOf(v, "calendar_content_color_style", CALENDAR_COLORS),
      ),
      show_dashboard_clock_buttons: optional(args.show_dashboard_clock_buttons, (v) => boolean(v, "show_dashboard_clock_buttons")),
      default_startup_tab: optional(args.default_startup_tab, (v) => oneOf(v, "default_startup_tab", STARTUP_TABS)),
    };
    const zone = optional(args.schedule_time_zone, (v) => {
      if (typeof v !== "string" || !isScheduleTimeZone(v)) throw new ToolError("schedule_time_zone must be an IANA time zone such as Europe/Oslo.");
      return v;
    });
    const defined = <T extends object>(o: T) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)) as Partial<T>;
    const change = { user_settings: defined(settings), schedule_time_zone: zone };
    if (Object.keys(change.user_settings).length === 0 && zone === undefined) {
      throw new ToolError("Give at least one setting to change.");
    }
    return change;
  },
} satisfies ToolSpec<SettingsChange>;
