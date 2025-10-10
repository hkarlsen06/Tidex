/**
 * Date and Timezone Utilities
 *
 * This module provides consistent date handling across the application.
 * All shift dates are stored as YYYY-MM-DD strings representing dates in the
 * user's local timezone (typically Europe/Oslo for Norwegian users).
 *
 * Key principles:
 * 1. Shift dates (shift_date) are date-only strings (YYYY-MM-DD)
 * 2. When comparing dates, always parse them in UTC to avoid timezone issues
 * 3. When getting "today" or "current month", use UTC to ensure consistency
 */

/**
 * Parses a YYYY-MM-DD date string as a UTC date at midnight
 * This ensures consistent date comparisons regardless of server timezone
 *
 * @param dateString - Date in YYYY-MM-DD format
 * @returns Date object representing midnight UTC on that date
 *
 * @example
 * parseDateAsUTC("2024-03-15") // Returns Date representing 2024-03-15T00:00:00.000Z
 */
export function parseDateAsUTC(dateString: string): Date {
  return new Date(dateString + "T00:00:00Z");
}

/**
 * Gets the current year and month in UTC
 * This should be used when filtering shifts by "current month"
 *
 * @returns Object with year and month (1-12)
 *
 * @example
 * getCurrentYearMonth() // { year: 2024, month: 3 } for March 2024
 */
export function getCurrentYearMonth(): { year: number; month: number } {
  const now = new Date();
  return {
    year: now.getUTCFullYear(),
    month: now.getUTCMonth() + 1, // Convert to 1-based month
  };
}

/**
 * Gets the previous month's year and month
 *
 * @returns Object with year and month (1-12)
 *
 * @example
 * getPreviousYearMonth() // { year: 2024, month: 2 } when current month is March 2024
 * getPreviousYearMonth() // { year: 2023, month: 12 } when current month is January 2024
 */
export function getPreviousYearMonth(): { year: number; month: number } {
  const now = new Date();
  const lastMonthDate = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1)
  );

  return {
    year: lastMonthDate.getUTCFullYear(),
    month: lastMonthDate.getUTCMonth() + 1,
  };
}

/**
 * Extracts year and month from a UTC date
 *
 * @param date - Date object
 * @returns Object with year and month (1-12)
 */
export function getYearMonth(date: Date): { year: number; month: number } {
  return {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
  };
}

/**
 * Checks if a shift date (YYYY-MM-DD string) belongs to a specific year and month
 *
 * @param shiftDate - Date string in YYYY-MM-DD format
 * @param targetYear - Year to check
 * @param targetMonth - Month to check (1-12)
 * @returns true if the shift is in the specified year/month
 *
 * @example
 * isDateInMonth("2024-03-15", 2024, 3) // true
 * isDateInMonth("2024-03-15", 2024, 4) // false
 */
export function isDateInMonth(
  shiftDate: string,
  targetYear: number,
  targetMonth: number
): boolean {
  const date = parseDateAsUTC(shiftDate);
  const { year, month } = getYearMonth(date);
  return year === targetYear && month === targetMonth;
}

/**
 * Gets today's date as a YYYY-MM-DD string in UTC
 * Useful for creating new shifts
 *
 * @returns Date string in YYYY-MM-DD format
 *
 * @example
 * getTodayAsDateString() // "2024-03-15"
 */
export function getTodayAsDateString(): string {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, "0");
  const day = String(now.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}
