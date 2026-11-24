import { isScheduleTimeZone } from "../scheduleTimeZone";
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
  oneOf,
  optional,
  optionalString,
  requiredString,
  text,
  time,
  updates,
} from "./args";
import type { ToolSpec } from "./registry";
import { addDays, MINUTES_PER_DAY, minutes, parseTime, ToolError } from "./shiftTimes";

// Tools for events, payroll adjustments and app settings, plus the row builders that match
// the iOS app's sync format.

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

/** Clean formatted view of an event, shared by get_schedule and save_event. */
export function eventView(e: EventFields & { id: string }) {
  const reminders = e.notification_minutes_array ?? [];
  return {
    id: e.id,
    date: e.start_date,
    ...(e.end_date !== e.start_date ? { end_date: e.end_date } : {}),
    all_day: e.is_all_day,
    ...(!e.is_all_day && e.start_time ? { start: e.start_time.slice(0, 5), end: e.end_time?.slice(0, 5) ?? null } : {}),
    note: e.note,
    ...(reminders.length > 0
      ? e.is_all_day
        ? { reminder_days_before: reminders.map((m) => m / MINUTES_PER_DAY), reminder_time: e.notification_anchor_time ?? null }
        : { reminder_minutes: reminders }
      : {}),
  };
}

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
  const dateStr = change.date ?? prev.start_date;
  const keepsKind = allDay === prev.is_all_day;
  const stored = prev.notification_minutes_array ?? [];
  if (allDay) {
    const length = keepsKind ? Math.round((Date.parse(prev.end_date) - Date.parse(prev.start_date)) / 86_400_000) : 0;
    return {
      note: change.note ?? prev.note,
      date: dateStr,
      end_date: change.end_date ?? addDays(dateStr, length),
      reminder_days_before: change.reminder_days_before ?? (keepsKind ? stored.map((m) => m / MINUTES_PER_DAY) : undefined),
      reminder_time: change.reminder_time ?? (keepsKind ? prev.notification_anchor_time : undefined),
      reminder_minutes: change.reminder_minutes,
    };
  }
  return {
    note: change.note ?? prev.note,
    date: dateStr,
    end_date: change.end_date,
    start: change.start ?? prev.start_time,
    end: change.end ?? prev.end_time,
    reminder_minutes: change.reminder_minutes ?? (keepsKind ? stored : undefined),
    reminder_time: change.reminder_time,
    reminder_days_before: change.reminder_days_before,
  };
}

const eventProperties = {
  id: { type: "string", description: "Event ID from get_schedule to update. Omit to create a new event." },
  note: { type: "string", maxLength: MAX_EVENT_NOTE, description: "Event description (required when creating)." },
  date: { ...date, description: "Event date, or first date of a multi-day all-day event (required when creating)." },
  end_date: { ...date, description: "Last date for a multi-day all-day event." },
  start: time,
  end: { ...endTime, description: "HH:mm, after start on the same day. 24:00 is midnight." },
  all_day: { type: "boolean", description: "Pass true when updating a timed event to make it all-day." },
  reminder_minutes: {
    type: "array",
    items: { type: "integer", minimum: 1, maximum: MAX_REMINDER_MINUTES },
    maxItems: MAX_REMINDERS,
    description: "Timed events: minutes before start. Empty list removes reminders.",
  },
  reminder_days_before: {
    type: "array",
    items: { type: "integer", minimum: 0, maximum: 2 },
    maxItems: 3,
    description: "All-day events: 0 (same day), 1 (day before), or 2 (two days before). Empty list removes reminders.",
  },
  reminder_time: { ...time, description: "All-day events: clock time reminders fire (required with reminder_days_before)." },
};

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

export const saveEvent = {
  definition: {
    name: "save_event",
    title: "Create or update event",
    description:
      "Creates a private calendar event (omit id) or updates an existing event (pass id from get_schedule). " +
      "Events with start and end are timed on one day; without them they are all-day and may span to end_date. " +
      "Reminders are local phone notifications scheduled the next time the app syncs.",
    inputSchema: { type: "object", properties: eventProperties, additionalProperties: false },
    annotations: { title: "Create or update event", ...adds },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, Object.keys(eventProperties));
    const id = optionalString(args.id, "id");
    const draft = parseEventDraft(args);
    const allDay = optional(args.all_day, (v) => boolean(v, "all_day"));

    if (id === undefined) {
      if (allDay === true && (draft.start !== undefined || draft.end !== undefined)) {
        throw new ToolError("all_day: true can't be combined with start or end.");
      }
      if (allDay === false && (draft.start === undefined || draft.end === undefined)) {
        throw new ToolError("Give start and end for a timed event.");
      }
      if (draft.note === undefined) throw new ToolError("note is required.");
      if (draft.date === undefined) throw new ToolError("date is required.");
      return { mode: "create" as const, fields: eventFields(draft as EventDraft) };
    }

    const change = { ...draft, all_day: allDay };
    if (Object.values(change).every((v) => v === undefined)) throw new ToolError("Give at least one field to update.");
    return { mode: "update" as const, id, change };
  },
} satisfies ToolSpec;

export const deleteEvent = {
  definition: {
    name: "delete_event",
    title: "Delete event",
    description: "Deletes a private calendar event by its id from get_schedule. Confirm with the user first.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", description: "Event ID from get_schedule." } },
      required: ["id"],
      additionalProperties: false,
    },
    annotations: { title: "Delete event", ...destructive },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["id"]);
    return { id: requiredString(args.id, "id") };
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

const adjustmentProperties = {
  id: { type: "string", description: "Adjustment ID from get_earnings to update. Omit to create a new adjustment." },
  job: jobRef,
  amount: { type: "number", description: "Amount in the job currency. Negative for a deduction. Not 0." },
  description: { type: "string", maxLength: MAX_DESCRIPTION, description: "Short label such as Christmas bonus." },
  category: { type: "string", enum: ADJUSTMENT_CATEGORIES, description: "Default correction." },
  tax_treatment: {
    type: "string",
    enum: TAX_TREATMENTS,
    description: "gross_taxable (default) is taxed like pay; net_manual is paid out as is. Forced to net_manual when the job has no tax.",
  },
  payout_date: { ...date, description: "Payday this adjustment is paid on (YYYY-MM-DD)." },
  earned_from: { ...date, description: "Optional start of earned period. Pass empty string with earned_to to clear." },
  earned_to: { ...date, description: "Optional end of earned period." },
  note: { type: "string", maxLength: MAX_ADJUSTMENT_NOTE, description: "Optional note. Pass empty string to clear." },
};

const parseAmount = (v: unknown) => {
  if (typeof v !== "number" || !Number.isFinite(v) || v === 0) throw new ToolError("amount must be a number other than 0.");
  return v;
};
const dateOrBlank = (field: string) => (v: unknown) => (v === "" ? "" : nearDate(v, field));

function parseAdjustment(args: Args) {
  return {
    job: optionalString(args.job, "job"),
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

export const savePayrollAdjustment = {
  definition: {
    name: "save_payroll_adjustment",
    title: "Create or update payroll adjustment",
    description:
      "Creates a bonus, back pay or correction on a payday (omit id) or updates an existing one (pass id from get_earnings). " +
      "When creating: pass amount, description and payout_date; omit job to use the default job.",
    inputSchema: { type: "object", properties: adjustmentProperties, additionalProperties: false },
    annotations: { title: "Create or update payroll adjustment", ...adds },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, Object.keys(adjustmentProperties));
    const id = optionalString(args.id, "id");
    const parsed = parseAdjustment(args);
    if (id === undefined) {
      if (parsed.amount === undefined) throw new ToolError("amount is required.");
      if (parsed.description === undefined) throw new ToolError("description is required.");
      if (parsed.payout_date === undefined) throw new ToolError("payout_date is required.");
      const draft = {
        ...parsed,
        amount: parsed.amount,
        description: parsed.description,
        payout_date: parsed.payout_date,
        category: parsed.category ?? "correction",
        earned_from: parsed.earned_from || undefined,
        earned_to: parsed.earned_to || undefined,
      };
      adjustmentFields(draft, { id: "", currency: "", taxEnabled: true });
      return { mode: "create" as const, ...draft };
    }
    if (Object.values(parsed).every((v) => v === undefined)) throw new ToolError("Give at least one field to update.");
    return { mode: "update" as const, id, change: parsed };
  },
} satisfies ToolSpec;

export const deletePayrollAdjustment = {
  definition: {
    name: "delete_payroll_adjustment",
    title: "Delete payroll adjustment",
    description: "Deletes a payroll adjustment by its id from get_earnings. Confirm with the user first.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", description: "Adjustment ID from get_earnings." } },
      required: ["id"],
      additionalProperties: false,
    },
    annotations: { title: "Delete payroll adjustment", ...destructive },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["id"]);
    return { id: requiredString(args.id, "id") };
  },
} satisfies ToolSpec;

// ---------- Settings ----------

export const THEMES = ["system", "light", "dark"] as const;
export const CALENDAR_COLORS = ["workplace", "monochrome"] as const;
export const STARTUP_TABS = ["home", "shifts", "stats", "sharing"] as const;

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
  calendar_color_style: {
    type: "string",
    enum: CALENDAR_COLORS,
    description: "workplace colors calendar entries by job; monochrome uses one color.",
  },
  show_clock_buttons: { type: "boolean", description: "Show clock in and out buttons on the home screen." },
  startup_tab: { type: "string", enum: STARTUP_TABS, description: "Tab the app opens on." },
  time_zone: {
    type: "string",
    description: "IANA time zone for shift clock times, such as Europe/Oslo.",
  },
};

export const updateSettings = {
  definition: {
    name: "update_settings",
    title: "Update settings",
    description:
      "Updates app settings and schedule time zone. Pass only what changes. " +
      "Notification settings are stored on the phone and can only be changed in the Tidex app.",
    inputSchema: { type: "object", properties: settingsProperties, additionalProperties: false },
    annotations: { title: "Update settings", ...updates },
  },
  scope: "write",
  parse: (args): SettingsChange => {
    allowOnly(args, Object.keys(settingsProperties));
    const settings = {
      theme: optional(args.theme, (v) => oneOf(v, "theme", THEMES)),
      calendar_content_color_style: optional(args.calendar_color_style, (v) => oneOf(v, "calendar_color_style", CALENDAR_COLORS)),
      show_dashboard_clock_buttons: optional(args.show_clock_buttons, (v) => boolean(v, "show_clock_buttons")),
      default_startup_tab: optional(args.startup_tab, (v) => oneOf(v, "startup_tab", STARTUP_TABS)),
    };
    const zone = optional(args.time_zone, (v) => {
      if (typeof v !== "string" || !isScheduleTimeZone(v)) throw new ToolError("time_zone must be an IANA time zone such as Europe/Oslo.");
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
