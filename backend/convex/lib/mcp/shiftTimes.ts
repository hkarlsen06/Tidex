// Dates and clock times as the MCP tools take them, stored the way the app's
// ShiftSchedule stores them: HH:mm, an end at or before the start is on the next day,
// and a midnight end is 24:00 so the shift stays on its own day.

export class ToolError extends Error {}

const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const TIME = /^([01]\d|2[0-3]):([0-5]\d)$/;
const MINUTES_PER_DAY = 24 * 60;

/** A real calendar date in YYYY-MM-DD form. */
export function parseDate(value: unknown, field: string): string {
  const match = typeof value === "string" ? DATE.exec(value) : null;
  if (match !== null) {
    const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
    if (date.toISOString().slice(0, 10) === value) return value as string;
  }
  throw new ToolError(`${field} must be a date like 2026-11-20.`);
}

/** HH:mm from 00:00 to 23:59. An end may also be 24:00. */
export function parseTime(value: unknown, field: string, allowEndOfDay = false): string {
  if (typeof value === "string" && (TIME.test(value) || (allowEndOfDay && value === "24:00"))) return value;
  throw new ToolError(`${field} must be a time like 08:30, from 00:00 to 23:59.`);
}

export function addDays(date: string, days: number): string {
  const shifted = new Date(`${date}T00:00:00Z`);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}

/** `from` to `to`, both included, at most `maxDays` long. */
export function parseRange(from: unknown, to: unknown, maxDays: number) {
  const start = parseDate(from, "from");
  const end = parseDate(to, "to");
  if (end < start) throw new ToolError("to must be on or after from.");
  if (addDays(start, maxDays - 1) < end) throw new ToolError(`The range can be at most ${maxDays} days.`);
  return { from: start, to: end };
}

const minutes = (time: string) => Number(time.slice(0, 2)) * 60 + Number(time.slice(3, 5));
const clock = (total: number) => {
  const wrapped = ((total % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  return `${String(Math.floor(wrapped / 60)).padStart(2, "0")}:${String(wrapped % 60).padStart(2, "0")}`;
};

/** ShiftSchedule.storedEndTime: a shift that ends at midnight ends at 24:00. */
export function storedEndTime(end: string, start: string): string {
  return end === "00:00" && start !== "00:00" ? "24:00" : end;
}

/** A shift's stored times from what a tool was given. Equal times are refused as a likely mistake. */
export function shiftTimes(start: string, end: string) {
  const stored = storedEndTime(end, start);
  if (minutes(stored) === minutes(start)) throw new ToolError("start and end can't be the same time.");
  return { start_time: start, end_time: stored };
}

/** A stored time such as "08:00:00" or "24:00" as HH:mm. */
export const clockTime = (stored: string) => stored.slice(0, 5);

/** True when the shift ends on the next day. */
export const endsNextDay = (start: string, end: string) => minutes(clockTime(end)) <= minutes(clockTime(start));

/**
 * ShiftSchedule.moved: changes what is given. A new start without a new end keeps the
 * shift's length.
 */
export function movedTimes(current: { start: string; end: string }, newStart?: string, newEnd?: string) {
  const start = newStart ?? clockTime(current.start);
  if (newEnd !== undefined) return shiftTimes(start, newEnd);
  if (newStart === undefined) return { start_time: start, end_time: clockTime(current.end) };
  const from = minutes(clockTime(current.start));
  let length = (minutes(clockTime(current.end)) - from) % MINUTES_PER_DAY;
  if (length <= 0) length += MINUTES_PER_DAY;
  // Not shiftTimes: a 24-hour shift keeps equal clock times, as in the app.
  return { start_time: start, end_time: storedEndTime(clock(minutes(start) + length), start) };
}
