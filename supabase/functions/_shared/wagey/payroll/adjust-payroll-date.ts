import { isInvalidPayrollDay } from '@/lib/holidays';
import type { Locale } from '@/lib/i18n';

/**
 * Adjusts a payroll date backwards to the last valid weekday (Tuesday-Friday)
 * if the original date falls on a weekend, Monday, or public holiday.
 *
 * This ensures employees receive payment on or before the expected date,
 * accounting for bank processing restrictions on weekends, Mondays, and holidays.
 *
 * @param payrollDay - Day of month (1-31)
 * @param month - Month (0-11, JavaScript Date format)
 * @param year - Full year (e.g., 2025)
 * @param locale - Locale for holiday detection (supports 'no', 'en')
 * @returns Adjusted Date object guaranteed to be a valid payroll day (Tue-Fri, non-holiday)
 *
 * @example
 * // Payroll day 15 falls on Saturday, Jan 15, 2025
 * adjustPayrollDate(15, 0, 2025, 'no') // Returns Friday, Jan 14, 2025
 *
 * @example
 * // Payroll day 17 falls on Monday, Feb 17, 2025
 * adjustPayrollDate(17, 1, 2025, 'no') // Returns Friday, Feb 14, 2025
 */
export function adjustPayrollDate(
  payrollDay: number,
  month: number,
  year: number,
  locale: Locale = 'no'
): Date {
  // Create initial date from payroll day
  let date = new Date(year, month, payrollDay);

  // Maximum iterations to prevent infinite loops (should never need more than 7 days)
  const maxIterations = 10;
  let iterations = 0;

  // Move backward until we find a valid payroll day (Tuesday-Friday, non-holiday)
  while (isInvalidPayrollDay(date, locale) && iterations < maxIterations) {
    // Move back one day
    date = new Date(date);
    date.setDate(date.getDate() - 1);
    iterations++;
  }

  // Safety check: if we hit max iterations, something is wrong
  if (iterations >= maxIterations) {
    console.error(
      `adjustPayrollDate: Could not find valid payroll day after ${maxIterations} iterations for payrollDay=${payrollDay}, month=${month}, year=${year}`
    );
  }

  return date;
}
