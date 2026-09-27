import { cleanTime } from "../_shared/wagey/time-utils.ts";
import { addDays, addOneDayIfCrossesMidnight, compareISODate } from "./date.ts";
import { calendarShiftLabel } from "./locale.ts";
import type {
  CalendarData,
  CalendarEventRow,
  CalendarFeedLocale,
  CalendarJobRow,
  CalendarShiftRow,
  FeedWindow,
  ProjectedRecurringShift,
} from "./types.ts";

const encoder = new TextEncoder();

type CalendarEventInput = {
  kind: "shift" | "recurring_shift" | "event";
  sourceId: string;
  occurrenceDate: string;
  updatedAt: string | null;
  summary: string;
  description: string | null;
  allDay?: boolean;
  startDate: string;
  endDate: string;
  startTime?: string | null;
  endTime?: string | null;
};

function bytes(value: string): number {
  return encoder.encode(value).byteLength;
}

export function foldICalendarLine(line: string): string {
  const chunks: string[] = [];
  let chunk = "";
  let limit = 75;

  for (const char of Array.from(line)) {
    const candidate = chunk + char;
    if (bytes(candidate) > limit) {
      chunks.push(chunk);
      chunk = char;
      limit = 74;
    } else {
      chunk = candidate;
    }
  }

  chunks.push(chunk);
  return chunks.map((part, index) => index === 0 ? part : ` ${part}`).join(
    "\r\n",
  );
}

export function escapeICalendarText(value: string): string {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll("\r\n", "\\n")
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\n")
    .replaceAll(";", "\\;")
    .replaceAll(",", "\\,");
}

function formatDateTime(date: string, time: string): string {
  const cleaned = cleanTime(time);
  // iCalendar has no 24:00, so end-of-day becomes midnight of the next day.
  if (cleaned === "24:00") return `${formatDate(addDays(date, 1))}T000000`;
  return `${formatDate(date)}T${cleaned.replace(":", "")}00`;
}

function formatDate(date: string): string {
  return date.replaceAll("-", "");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function stableUid(event: CalendarEventInput): Promise<string> {
  const digest = await sha256Hex(
    `${event.kind}:${event.sourceId}:${event.occurrenceDate}`,
  );
  return `${digest}@tidex.no`;
}

function updatedAtStamp(updatedAt: string | null): string {
  if (!updatedAt) return "19700101T000000Z";
  const date = new Date(updatedAt);
  if (Number.isNaN(date.getTime())) return "19700101T000000Z";
  return date.toISOString().replaceAll("-", "").replaceAll(":", "").replace(
    /\.\d{3}Z$/,
    "Z",
  );
}

async function serializeEvent(event: CalendarEventInput): Promise<string[]> {
  const lines = [
    "BEGIN:VEVENT",
    `UID:${await stableUid(event)}`,
    `DTSTAMP:${updatedAtStamp(event.updatedAt)}`,
    `SUMMARY:${escapeICalendarText(event.summary)}`,
  ];

  if (event.allDay) {
    lines.push(`DTSTART;VALUE=DATE:${formatDate(event.startDate)}`);
    lines.push(`DTEND;VALUE=DATE:${formatDate(addDays(event.endDate, 1))}`);
  } else {
    lines.push(
      `DTSTART:${formatDateTime(event.startDate, event.startTime ?? "00:00")}`,
    );
    lines.push(
      `DTEND:${formatDateTime(event.endDate, event.endTime ?? "00:00")}`,
    );
  }

  if (event.description) {
    lines.push(`DESCRIPTION:${escapeICalendarText(event.description)}`);
  }

  lines.push("END:VEVENT");
  return lines;
}

function jobName(
  jobsById: ReadonlyMap<string, CalendarJobRow>,
  jobId: string | null,
): string | null {
  if (!jobId) return null;
  return jobsById.get(jobId)?.name ?? null;
}

function shiftInput(
  shift: CalendarShiftRow,
  jobsById: ReadonlyMap<string, CalendarJobRow>,
  locale: CalendarFeedLocale,
): CalendarEventInput {
  const startTime = cleanTime(shift.start_time);
  const endTime = cleanTime(shift.end_time);
  const name = jobName(jobsById, shift.job_id);
  const shiftLabel = calendarShiftLabel(locale);

  return {
    kind: "shift",
    sourceId: shift.id,
    occurrenceDate: shift.shift_date,
    updatedAt: shift.updated_at,
    summary: name ? `${shiftLabel}: ${name}` : shiftLabel,
    description: shift.note,
    startDate: shift.shift_date,
    endDate: addOneDayIfCrossesMidnight(shift.shift_date, startTime, endTime),
    startTime,
    endTime,
  };
}

function recurringShiftInput(
  shift: ProjectedRecurringShift,
  jobsById: ReadonlyMap<string, CalendarJobRow>,
  locale: CalendarFeedLocale,
): CalendarEventInput {
  const startTime = cleanTime(shift.start_time);
  const endTime = cleanTime(shift.end_time);
  const name = jobName(jobsById, shift.job_id);
  const shiftLabel = calendarShiftLabel(locale);

  return {
    kind: "recurring_shift",
    sourceId: shift.id,
    occurrenceDate: shift.occurrenceDate,
    updatedAt: shift.updated_at,
    summary: name ? `${shiftLabel}: ${name}` : shiftLabel,
    description: shift.note,
    startDate: shift.occurrenceDate,
    endDate: addOneDayIfCrossesMidnight(
      shift.occurrenceDate,
      startTime,
      endTime,
    ),
    startTime,
    endTime,
  };
}

function eventInput(event: CalendarEventRow): CalendarEventInput {
  return {
    kind: "event",
    sourceId: event.id,
    occurrenceDate: event.start_date,
    updatedAt: event.updated_at,
    summary: event.note,
    description: null,
    allDay: event.is_all_day,
    startDate: event.start_date,
    endDate: event.end_date,
    startTime: event.start_time,
    endTime: event.end_time,
  };
}

function sortEvents(
  left: CalendarEventInput,
  right: CalendarEventInput,
): number {
  const dateCompare = compareISODate(left.startDate, right.startDate);
  if (dateCompare !== 0) return dateCompare;
  return (left.startTime ?? "").localeCompare(right.startTime ?? "");
}

export async function buildICalendarFeed(
  data: CalendarData,
  projectedRecurringShifts: ProjectedRecurringShift[],
  _window: FeedWindow,
  locale: CalendarFeedLocale = "en",
): Promise<string> {
  const jobsById = new Map(data.jobs.map((job) => [job.id, job]));
  const events = [
    ...data.shifts.map((shift) => shiftInput(shift, jobsById, locale)),
    ...projectedRecurringShifts.map((shift) =>
      recurringShiftInput(shift, jobsById, locale)
    ),
    ...data.events.map(eventInput),
  ].sort(sortEvents);

  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Tidex//Calendar Subscription//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:Tidex",
  ];

  for (const event of events) {
    lines.push(...await serializeEvent(event));
  }

  lines.push("END:VCALENDAR");
  return `${lines.map(foldICalendarLine).join("\r\n")}\r\n`;
}
