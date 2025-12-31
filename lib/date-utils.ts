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
 * Gets the current year and month in Europe/Oslo timezone
 * This ensures SSR loads the correct month for Norwegian users
 *
 * @returns Object with year and month (1-12)
 *
 * @example
 * getCurrentYearMonth() // { year: 2024, month: 3 } for March 2024
 */
export function getCurrentYearMonth(): { year: number; month: number } {
  // Use Europe/Oslo timezone (UTC+1/+2 with DST) to match Norwegian users
  // This prevents SSR/client mismatch during the hour around midnight
  const osloDateStr = new Date().toLocaleDateString('en-CA', { timeZone: 'Europe/Oslo' });
  const [year, month] = osloDateStr.split('-').map(Number);
  return { year, month };
}

/**
 * Gets the previous month's year and month (relative to Europe/Oslo timezone)
 *
 * @returns Object with year and month (1-12)
 *
 * @example
 * getPreviousYearMonth() // { year: 2024, month: 2 } when current month is March 2024
 * getPreviousYearMonth() // { year: 2023, month: 12 } when current month is January 2024
 */
export function getPreviousYearMonth(): { year: number; month: number } {
  const { year, month } = getCurrentYearMonth();
  // Handle year rollover (January -> December of previous year)
  if (month === 1) {
    return { year: year - 1, month: 12 };
  }
  return { year, month: month - 1 };
}

/**
 * Gets the next month's year and month (relative to Europe/Oslo timezone)
 *
 * @returns Object with year and month (1-12)
 *
 * @example
 * getNextYearMonth() // { year: 2024, month: 4 } when current month is March 2024
 * getNextYearMonth() // { year: 2025, month: 1 } when current month is December 2024
 */
export function getNextYearMonth(): { year: number; month: number } {
  const { year, month } = getCurrentYearMonth();
  // Handle year rollover (December -> January of next year)
  if (month === 12) {
    return { year: year + 1, month: 1 };
  }
  return { year, month: month + 1 };
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

/**
 * Get start of current year (YYYY-01-01)
 * Useful for loading full year of data
 *
 * @returns Date string in YYYY-MM-DD format
 *
 * @example
 * getCurrentYearStart() // "2025-01-01"
 */
export function getCurrentYearStart(): string {
  const now = new Date();
  return `${now.getUTCFullYear()}-01-01`;
}

/**
 * Get end of current year (YYYY-12-31)
 * Useful for loading full year of data
 *
 * @returns Date string in YYYY-MM-DD format
 *
 * @example
 * getCurrentYearEnd() // "2025-12-31"
 */
export function getCurrentYearEnd(): string {
  const now = new Date();
  return `${now.getUTCFullYear()}-12-31`;
}

/**
 * Get start of a specific month (YYYY-MM-01)
 * Useful for loading month-specific data
 *
 * @param year - Year (e.g., 2025)
 * @param month - Month (1-12)
 * @returns Date string in YYYY-MM-DD format
 *
 * @example
 * getMonthStart(2025, 3) // "2025-03-01"
 */
export function getMonthStart(year: number, month: number): string {
  return `${year}-${String(month).padStart(2, "0")}-01`;
}

/**
 * Get end of a specific month (YYYY-MM-last day)
 * Handles different month lengths including leap years
 *
 * @param year - Year (e.g., 2025)
 * @param month - Month (1-12)
 * @returns Date string in YYYY-MM-DD format
 *
 * @example
 * getMonthEnd(2025, 2) // "2025-02-28"
 * getMonthEnd(2024, 2) // "2024-02-29" (leap year)
 */
export function getMonthEnd(year: number, month: number): string {
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return `${year}-${String(month).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`;
}

/**
 * Calculate ISO week number for a given date
 * Used for calendar week display
 *
 * @param date - Date object
 * @returns ISO week number (1-53)
 *
 * @example
 * getISOWeek(new Date('2024-01-01')) // 1
 */
export function getISOWeek(date: Date): number {
  const d = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())
  );
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNumber = Math.ceil(
    ((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7
  );
  return weekNumber;
}

/**
 * Format weekday name as 2-letter abbreviation
 * Supports Norwegian and English locales
 *
 * @param date - Date object
 * @param locale - Locale code ('no' or 'en')
 * @returns 2-letter weekday abbreviation
 *
 * @example
 * formatWeekdayAbbreviation(new Date('2024-03-15'), 'en') // 'FR'
 * formatWeekdayAbbreviation(new Date('2024-03-15'), 'no') // 'FR'
 */
export function formatWeekdayAbbreviation(date: Date, locale: string): string {
  const day = date.getDay();
  const shortNames = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
  const shortNamesNb = ['SØ', 'MA', 'TI', 'ON', 'TO', 'FR', 'LØ'];
  const names = locale === 'no' ? shortNamesNb : shortNames;
  return names[day];
}

/**
 * Clean time string to HH:mm format
 * Handles various input formats from database/API
 *
 * @param time - Time string in various formats
 * @returns Time string in HH:mm format
 *
 * @example
 * cleanTime("12:30:00+01:00") // "12:30"
 * cleanTime("12:30:00") // "12:30"
 * cleanTime("12:30") // "12:30"
 */
export function cleanTime(time: string): string {
  if (!time) return time;

  let cleaned = time;
  const plusIndex = cleaned.indexOf('+');
  const minusIndex = cleaned.lastIndexOf('-');

  if (plusIndex > 0) {
    cleaned = cleaned.substring(0, plusIndex);
  } else if (minusIndex > 2) {
    cleaned = cleaned.substring(0, minusIndex);
  }

  return cleaned.substring(0, 5);
}
