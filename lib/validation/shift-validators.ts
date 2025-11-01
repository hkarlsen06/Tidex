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
