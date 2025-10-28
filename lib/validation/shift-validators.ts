/**
 * Validation utilities for shift-related data
 *
 * These validators are used across multiple server actions to ensure
 * consistent validation of dates, times, and shift types.
 */

/**
 * Validates ISO date format (YYYY-MM-DD)
 * @param input - String to validate
 * @returns true if string matches YYYY-MM-DD format
 *
 * @example
 * isISODate("2025-01-15") // true
 * isISODate("2025-1-5")   // false
 * isISODate("15-01-2025") // false
 */
export function isISODate(input: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(input);
}

/**
 * Validates time format (HH:MM)
 * @param input - String to validate
 * @returns true if string matches HH:MM format
 *
 * @example
 * isHHMM("09:30") // true
 * isHHMM("9:30")  // false
 * isHHMM("09:3")  // false
 */
export function isHHMM(input: string): boolean {
  return /^\d{2}:\d{2}$/.test(input);
}

/**
 * Determines shift type from ISO date based on day of week
 * @param iso - ISO date string (YYYY-MM-DD)
 * @returns 0 for weekday, 1 for Saturday, 2 for Sunday
 *
 * @example
 * shiftTypeFromISODate("2025-01-15") // 0 (Wednesday)
 * shiftTypeFromISODate("2025-01-18") // 1 (Saturday)
 * shiftTypeFromISODate("2025-01-19") // 2 (Sunday)
 */
export function shiftTypeFromISODate(iso: string): 0 | 1 | 2 {
  const d = new Date(`${iso}T00:00:00Z`);
  const weekday = d.getUTCDay();
  return weekday === 6 ? 1 : weekday === 0 ? 2 : 0;
}
