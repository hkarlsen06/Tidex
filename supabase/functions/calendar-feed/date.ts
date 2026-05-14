import { parseDateAsUTC } from "../_shared/wagey/date-utils.ts";
import { toISODate } from "../_shared/wagey/recurring/utils.ts";
import type { FeedWindow } from "./types.ts";

const DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_TIME_ZONE = "Europe/Oslo";

function localISODate(date: Date, timeZone = DEFAULT_TIME_ZONE): string {
  return date.toLocaleDateString("en-CA", { timeZone });
}

export function addDays(isoDate: string, days: number): string {
  const date = parseDateAsUTC(isoDate);
  date.setUTCDate(date.getUTCDate() + days);
  return toISODate(date);
}

export function addMonthsClamped(isoDate: string, months: number): string {
  const source = parseDateAsUTC(isoDate);
  const targetYear = source.getUTCFullYear();
  const targetMonth = source.getUTCMonth() + months;
  const targetMonthStart = new Date(Date.UTC(targetYear, targetMonth, 1));
  const lastDay = new Date(
    Date.UTC(
      targetMonthStart.getUTCFullYear(),
      targetMonthStart.getUTCMonth() + 1,
      0,
    ),
  ).getUTCDate();
  const day = Math.min(source.getUTCDate(), lastDay);
  return toISODate(
    new Date(Date.UTC(
      targetMonthStart.getUTCFullYear(),
      targetMonthStart.getUTCMonth(),
      day,
    )),
  );
}

export function compareISODate(left: string, right: string): number {
  return left.localeCompare(right);
}

export function createFeedWindow(
  now = new Date(),
  timeZone = DEFAULT_TIME_ZONE,
): FeedWindow {
  const today = localISODate(now, timeZone);
  return {
    startDate: addDays(today, -90),
    endDate: addMonthsClamped(today, 12),
  };
}

export function monthsBetweenInclusive(
  window: FeedWindow,
): Array<{ year: number; month: number }> {
  const start = parseDateAsUTC(window.startDate);
  const end = parseDateAsUTC(window.endDate);
  const current = new Date(
    Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1),
  );
  const final = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), 1));
  const months: Array<{ year: number; month: number }> = [];

  while (current.getTime() <= final.getTime()) {
    months.push({
      year: current.getUTCFullYear(),
      month: current.getUTCMonth() + 1,
    });
    current.setUTCMonth(current.getUTCMonth() + 1);
  }

  return months;
}

export function addOneDayIfCrossesMidnight(
  date: string,
  startTime: string,
  endTime: string,
): string {
  return endTime <= startTime ? addDays(date, 1) : date;
}

export function dateOnlyDurationDays(
  startDate: string,
  inclusiveEndDate: string,
): number {
  const start = parseDateAsUTC(startDate).getTime();
  const end = parseDateAsUTC(inclusiveEndDate).getTime();
  return Math.max(1, Math.floor((end - start) / DAY_MS) + 1);
}
