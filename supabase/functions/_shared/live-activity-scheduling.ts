import type {
  CustomPauseWindows,
  CustomSupplementsData,
  ShiftRow,
} from "./wagey/payroll/types.ts";
import type { EndCondition, SelectedDays } from "./wagey/recurring/types.ts";
import { generateVirtualShiftsForMonth } from "./wagey/recurring/utils.ts";

export interface LiveActivityRegularShift extends ShiftRow {
  job_id: string;
}

export interface LiveActivityRecurringShift {
  id: string;
  user_id: string;
  job_id: string;
  start_time: string;
  end_time: string;
  repeat_interval_weeks: number;
  selected_days: SelectedDays;
  end_condition: EndCondition;
  exclusions: string[] | null;
  date_specific_pause_windows?: Record<string, CustomPauseWindows> | null;
  date_specific_supplements?: Record<string, CustomSupplementsData> | null;
}

export interface LocalClock {
  date: string;
  previousDate: string;
  minuteOfDay: number;
}

export function normalizeStoredTime(value: string): string {
  const match = value.match(/^(\d{2}):(\d{2})/);
  if (!match) throw new Error(`Invalid shift time: ${value}`);
  return `${match[1]}:${match[2]}`;
}

function timeMinutes(value: string): number {
  const [hours, minutes] = normalizeStoredTime(value).split(":").map(Number);
  return hours * 60 + minutes;
}

export function localClock(now: Date, timeZone: string): LocalClock {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((candidate) => candidate.type === type)?.value;
  const year = part("year");
  const month = part("month");
  const day = part("day");
  const hour = Number(part("hour"));
  const minute = Number(part("minute"));
  if (
    !year || !month || !day || !Number.isFinite(hour) ||
    !Number.isFinite(minute)
  ) {
    throw new Error(`Unable to resolve local clock for ${timeZone}`);
  }
  const date = `${year}-${month}-${day}`;
  const previousDate = new Date(`${date}T00:00:00Z`);
  previousDate.setUTCDate(previousDate.getUTCDate() - 1);
  return {
    date,
    previousDate: previousDate.toISOString().slice(0, 10),
    minuteOfDay: hour * 60 + minute,
  };
}

export function isShiftOngoingAtLocalClock(
  shift: Pick<ShiftRow, "shift_date" | "start_time" | "end_time">,
  clock: LocalClock,
): boolean {
  const start = timeMinutes(shift.start_time);
  const end = timeMinutes(shift.end_time);
  if (end >= start) {
    return shift.shift_date === clock.date &&
      clock.minuteOfDay >= start && clock.minuteOfDay < end;
  }
  return (shift.shift_date === clock.date && clock.minuteOfDay >= start) ||
    (shift.shift_date === clock.previousDate && clock.minuteOfDay < end);
}

function monthForDate(date: string): { year: number; month: number } {
  return { year: Number(date.slice(0, 4)), month: Number(date.slice(5, 7)) };
}

export function projectedRecurringShifts(
  recurringShifts: LiveActivityRecurringShift[],
  dates: string[],
): LiveActivityRegularShift[] {
  const requestedDates = new Set(dates);
  const months = new Map<string, { year: number; month: number }>();
  for (const date of requestedDates) {
    const month = monthForDate(date);
    months.set(`${month.year}-${month.month}`, month);
  }

  return recurringShifts.flatMap((recurring) =>
    Array.from(months.values()).flatMap((month) =>
      generateVirtualShiftsForMonth(month, {
        start_time: normalizeStoredTime(recurring.start_time),
        end_time: normalizeStoredTime(recurring.end_time),
        repeat_interval_weeks: recurring.repeat_interval_weeks as
          | 0
          | 1
          | 2
          | 3
          | 4
          | 5
          | 6
          | 7
          | 8,
        selected_days: recurring.selected_days,
        end_condition: recurring.end_condition,
        exclusions: recurring.exclusions ?? [],
      }).filter((occurrence) => requestedDates.has(occurrence.date)).map((
        occurrence,
      ) => ({
        id: `virtual-${recurring.id}-${occurrence.date}`,
        user_id: recurring.user_id,
        job_id: recurring.job_id,
        shift_date: occurrence.date,
        start_time: normalizeStoredTime(recurring.start_time),
        end_time: normalizeStoredTime(recurring.end_time),
        custom_pause_windows:
          recurring.date_specific_pause_windows?.[occurrence.date] ?? null,
        custom_supplements:
          recurring.date_specific_supplements?.[occurrence.date] ?? null,
      }))
    )
  );
}

export function findOngoingShift(
  now: Date,
  timeZone: string,
  regularShifts: LiveActivityRegularShift[],
  recurringShifts: LiveActivityRecurringShift[],
): LiveActivityRegularShift | null {
  const clock = localClock(now, timeZone);
  const relevantRegular = regularShifts.filter((shift) =>
    shift.shift_date === clock.date || shift.shift_date === clock.previousDate
  );
  const regularDates = new Set(
    relevantRegular.map((shift) => shift.shift_date),
  );
  const virtual = projectedRecurringShifts(recurringShifts, [
    clock.previousDate,
    clock.date,
  ])
    .filter((shift) => !regularDates.has(shift.shift_date));

  return [...relevantRegular, ...virtual]
    .filter((shift) => isShiftOngoingAtLocalClock(shift, clock))
    .sort((lhs, rhs) =>
      lhs.shift_date.localeCompare(rhs.shift_date) ||
      normalizeStoredTime(lhs.start_time).localeCompare(
        normalizeStoredTime(rhs.start_time),
      ) ||
      lhs.id.localeCompare(rhs.id)
    )[0] ?? null;
}

function zonedParts(date: Date, timeZone: string): Record<string, number> {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  return Object.fromEntries(
    parts.filter((part) => part.type !== "literal")
      .map((part) => [part.type, Number(part.value)]),
  );
}

export function zonedShiftRange(
  shift: Pick<ShiftRow, "shift_date" | "start_time" | "end_time">,
  timeZone: string,
): { startDate: Date; endDate: Date } {
  const toInstant = (date: string, time: string): Date => {
    const normalized = normalizeStoredTime(time);
    const utcGuess = Date.parse(`${date}T${normalized}:00Z`);
    let instant = utcGuess;
    for (let attempt = 0; attempt < 2; attempt++) {
      const parts = zonedParts(new Date(instant), timeZone);
      const representedAsUTC = Date.UTC(
        parts.year,
        parts.month - 1,
        parts.day,
        parts.hour,
        parts.minute,
        parts.second,
      );
      instant = utcGuess - (representedAsUTC - instant);
    }
    return new Date(instant);
  };

  const startDate = toInstant(shift.shift_date, shift.start_time);
  let endDateString = shift.shift_date;
  if (timeMinutes(shift.end_time) < timeMinutes(shift.start_time)) {
    const nextDate = new Date(`${shift.shift_date}T00:00:00Z`);
    nextDate.setUTCDate(nextDate.getUTCDate() + 1);
    endDateString = nextDate.toISOString().slice(0, 10);
  }
  return { startDate, endDate: toInstant(endDateString, shift.end_time) };
}
