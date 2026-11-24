import { addDays, parseDate, ToolError } from "./shiftTimes";

// Port of ios/Shared/PayPeriod.swift so the MCP server computes the same pay windows,
// nominal payout dates and half-tax months as the iOS app.

export type StoredPayPeriod =
  | { type: "monthly"; startDay: number; payoutMonthOffset: 0 | 1 }
  | { type: "biweekly"; anchorEnd: string; payoutDelayDays: number };

export type PayWindow = {
  start: string;
  end: string;
  /** Nominal payday before weekend and holiday adjustment. Used for tax lookups. */
  payoutDate: string;
  /** 1-12 month of payoutDate. */
  payoutMonth: number;
};

export const CALENDAR_MONTH_PERIOD: StoredPayPeriod = { type: "monthly", startDay: 1, payoutMonthOffset: 1 };

export const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"] as const;

const MONTH = /^(\d{4})-(0[1-9]|1[0-2])$/;

/** Parses a stored jobs.pay_period column, falling back to calendar month like PayPeriod.swift. */
export function parseStoredPayPeriod(stored: unknown): StoredPayPeriod {
  const p = (stored ?? {}) as Record<string, unknown>;
  const int = (v: unknown) => (typeof v === "number" && Number.isInteger(v) ? v : Number.NaN);
  if (
    p.type === "biweekly" &&
    typeof p.anchorEnd === "string" &&
    isValidISODate(p.anchorEnd) &&
    int(p.payoutDelayDays) >= 0 &&
    int(p.payoutDelayDays) <= 27
  ) {
    return { type: "biweekly", anchorEnd: p.anchorEnd, payoutDelayDays: p.payoutDelayDays as number };
  }
  if (
    p.type === "monthly" &&
    int(p.startDay) >= 1 &&
    int(p.startDay) <= 28 &&
    (p.payoutMonthOffset === 0 || p.payoutMonthOffset === 1)
  ) {
    return { type: "monthly", startDay: p.startDay as number, payoutMonthOffset: p.payoutMonthOffset };
  }
  return CALENDAR_MONTH_PERIOD;
}

function isValidISODate(value: string): boolean {
  try {
    parseDate(value, "date");
    return true;
  } catch {
    return false;
  }
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

function formatYMD(year: number, month: number, day: number): string {
  return `${String(year).padStart(4, "0")}-${pad2(month)}-${pad2(day)}`;
}

function dateParts(iso: string): { year: number; month: number; day: number } {
  return {
    year: Number(iso.slice(0, 4)),
    month: Number(iso.slice(5, 7)),
    day: Number(iso.slice(8, 10)),
  };
}

function prevYearMonth(year: number, month: number): { year: number; month: number } {
  return month === 1 ? { year: year - 1, month: 12 } : { year, month: month - 1 };
}

function nextYearMonth(year: number, month: number): { year: number; month: number } {
  return month === 12 ? { year: year + 1, month: 1 } : { year, month: month + 1 };
}

function daysBetween(fromISO: string, toISO: string): number {
  return Math.round((Date.parse(`${toISO}T00:00:00Z`) - Date.parse(`${fromISO}T00:00:00Z`)) / 86_400_000);
}

/** Matches PayoutSchedule.canPayInEndMonth. */
function effectivePayoutMonthOffset(startDay: number, storedOffset: 0 | 1, payrollDay: number): 0 | 1 {
  return startDay > 1 && payrollDay >= startDay ? storedOffset : 1;
}

function monthlyWindow(startYear: number, startMonth: number, startDay: number, storedOffset: 0 | 1, payrollDay: number): PayWindow {
  const start = formatYMD(startYear, startMonth, startDay);
  const next = nextYearMonth(startYear, startMonth);
  const end = addDays(formatYMD(next.year, next.month, startDay), -1);
  const endParts = dateParts(end);
  let payout = { year: endParts.year, month: endParts.month };
  const offset = effectivePayoutMonthOffset(startDay, storedOffset, payrollDay);
  for (let i = 0; i < offset; i++) payout = nextYearMonth(payout.year, payout.month);
  const clampedDay = Math.min(Math.max(payrollDay, 1), daysInMonth(payout.year, payout.month));
  const payoutDate = formatYMD(payout.year, payout.month, clampedDay);
  return { start, end, payoutDate, payoutMonth: payout.month };
}

function biweeklyWindow(anchorEnd: string, payoutDelayDays: number, blockOffset: number): PayWindow {
  const end = addDays(anchorEnd, blockOffset * 14);
  const start = addDays(end, -13);
  const payoutDate = addDays(end, payoutDelayDays);
  return { start, end, payoutDate, payoutMonth: Number(payoutDate.slice(5, 7)) };
}

/** The pay window containing a worked date (matches PayoutSchedule.window(containing:)). */
export function payWindowForDate(period: StoredPayPeriod, payrollDay: number, dateISO: string): PayWindow {
  if (period.type === "monthly") {
    const { year, month, day } = dateParts(dateISO);
    const startYM = day < period.startDay ? prevYearMonth(year, month) : { year, month };
    return monthlyWindow(startYM.year, startYM.month, period.startDay, period.payoutMonthOffset, payrollDay);
  }
  const days = daysBetween(period.anchorEnd, dateISO);
  const blocks = Math.ceil(days / 14) || 0;
  return biweeklyWindow(period.anchorEnd, period.payoutDelayDays, blocks);
}

/** Nominal payout date for a worked date (matches PayoutSchedule.payoutDate(for:)). */
export function payoutDateForDate(period: StoredPayPeriod, payrollDay: number, dateISO: string): string {
  return payWindowForDate(period, payrollDay, dateISO).payoutDate;
}

/** Pay windows whose nominal payday falls in (year, month), earliest first. */
export function payWindowsPaidInMonth(period: StoredPayPeriod, payrollDay: number, year: number, month: number): PayWindow[] {
  if (period.type === "monthly") {
    let endYM = { year, month };
    const offset = effectivePayoutMonthOffset(period.startDay, period.payoutMonthOffset, payrollDay);
    for (let i = 0; i < offset; i++) endYM = prevYearMonth(endYM.year, endYM.month);
    const startYM = period.startDay === 1 ? endYM : prevYearMonth(endYM.year, endYM.month);
    return [monthlyWindow(startYM.year, startYM.month, period.startDay, period.payoutMonthOffset, payrollDay)];
  }
  const firstDay = formatYMD(year, month, 1);
  const lastDay = formatYMD(year, month, daysInMonth(year, month));
  const daysToStart = daysBetween(period.anchorEnd, firstDay);
  let block = Math.ceil((daysToStart - period.payoutDelayDays) / 14) || 0;
  const windows: PayWindow[] = [];
  for (;;) {
    const w = biweeklyWindow(period.anchorEnd, period.payoutDelayDays, block);
    if (w.payoutDate > lastDay) break;
    if (w.payoutDate >= firstDay) windows.push(w);
    block += 1;
  }
  return windows;
}

/** Parses YYYY-MM into its calendar bounds. */
export function parseMonth(value: unknown, field = "month"): { monthKey: string; year: number; month: number; from: string; to: string } {
  const match = typeof value === "string" ? MONTH.exec(value) : null;
  if (match === null) throw new ToolError(`${field} must be YYYY-MM, like 2026-11.`);
  const year = Number(match[1]);
  const month = Number(match[2]);
  return {
    monthKey: value as string,
    year,
    month,
    from: formatYMD(year, month, 1),
    to: formatYMD(year, month, daysInMonth(year, month)),
  };
}

export function weekdayName(dateISO: string): (typeof WEEKDAYS)[number] {
  return WEEKDAYS[new Date(`${dateISO}T00:00:00Z`).getUTCDay()]!;
}

/** Current local date (YYYY-MM-DD) and clock time (HH:mm) in an IANA time zone (UTC fallback). */
export function localNowInTimeZone(timeZone: string | null | undefined, at: Date = new Date()): { today: string; now: string } {
  if (!timeZone) {
    return { today: at.toISOString().slice(0, 10), now: at.toISOString().slice(11, 16) };
  }
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(at);
    const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
    const hour = get("hour") === "24" ? "00" : get("hour");
    return {
      today: `${get("year")}-${get("month")}-${get("day")}`,
      now: `${hour}:${get("minute")}`,
    };
  } catch {
    return {
      today: at.toISOString().slice(0, 10),
      now: at.toISOString().slice(11, 16),
    };
  }
}
