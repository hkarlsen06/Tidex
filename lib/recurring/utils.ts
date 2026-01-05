/**
 * Recurring utilities for recurring shift patterns
 *
 * Provides functions for:
 * - Calculating date windows for navigation
 * - Generating virtual shift occurrences for a given month
 * - Phase testing (week-based repetition patterns)
 * - Date formatting and weekday calculations
 */

import type { SelectedDays, EndCondition, RecurringDraft, RecurringVirtualShift, DateWindow } from './types';
import { parseDateAsUTC, getMonthStart, getMonthEnd } from '@/lib/date-utils';

/**
 * Convert a Date to ISO date string (YYYY-MM-DD) in UTC
 */
export function toISODate(date: Date): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Get weekday key (0-6) from a Date object
 * 0 = Sunday, 1 = Monday, ..., 6 = Saturday
 */
export function getWeekdayKey(date: Date): '0' | '1' | '2' | '3' | '4' | '5' | '6' {
  return String(date.getUTCDay()) as '0' | '1' | '2' | '3' | '4' | '5' | '6';
}

/**
 * Get ISO week number for a date
 * Uses ISO 8601 standard (week starts on Monday)
 */
export function getISOWeek(date: Date): number {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNum = d.getUTCDay() || 7; // Convert Sunday (0) to 7
  d.setUTCDate(d.getUTCDate() + 4 - dayNum); // Set to nearest Thursday
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNum = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return weekNum;
}

/**
 * Get ISO week year for a date
 * (Week year can differ from calendar year at year boundaries)
 */
export function getISOWeekYear(date: Date): number {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  return d.getUTCFullYear();
}

/**
 * Check if a date is in phase with an anchor date given an interval
 *
 * @param dateISO - ISO date to check (YYYY-MM-DD)
 * @param anchorISO - Anchor date (YYYY-MM-DD)
 * @param interval - Repetition interval (0 = every week, 1 = every 2 weeks, etc.)
 * @returns true if date is in phase with anchor
 *
 * @example
 * isInPhase('2025-11-03', '2025-10-27', 0) // true (every week)
 * isInPhase('2025-11-03', '2025-10-27', 1) // true (every 2 weeks, 1 week apart)
 * isInPhase('2025-11-10', '2025-10-27', 1) // false (2 weeks apart, wrong phase)
 */
export function isInPhase(dateISO: string, anchorISO: string, interval: number): boolean {
  // interval 0 means every week, always in phase
  if (interval === 0) return true;

  const date = parseDateAsUTC(dateISO);
  const anchor = parseDateAsUTC(anchorISO);

  // Calculate the number of days between the two dates
  const daysDiff = Math.floor((date.getTime() - anchor.getTime()) / (1000 * 60 * 60 * 24));

  // Calculate the number of weeks between the dates
  const weeksDiff = Math.floor(daysDiff / 7);

  // Check if the week difference is divisible by (interval + 1)
  // interval 1 = every 2 weeks, interval 2 = every 3 weeks, etc.
  return weeksDiff % (interval + 1) === 0;
}

/**
 * Resolve the navigable date window from anchors and end condition
 *
 * @param anchors - Selected anchor dates by weekday
 * @param endCondition - End condition (null, months, years, or end_date)
 * @param previewMonthsIfNone - Months to preview if no end (default: 6)
 * @returns Date window with min/max months, or null if no anchors
 */
export function resolveEndWindow(
  anchors: SelectedDays,
  endCondition: EndCondition,
  previewMonthsIfNone = 6
): DateWindow | null {
  const anchorDates = Object.values(anchors).map((iso) => parseDateAsUTC(iso));
  if (anchorDates.length === 0) return null;

  // Find earliest anchor
  const minAnchor = new Date(Math.min(...anchorDates.map((d) => d.getTime())));
  let maxDate: Date;

  if (endCondition === null) {
    // No end: show preview for N months
    maxDate = new Date(Date.UTC(
      minAnchor.getUTCFullYear(),
      minAnchor.getUTCMonth() + previewMonthsIfNone,
      minAnchor.getUTCDate()
    ));
  } else if (endCondition.type === 'months') {
    // Add N months from earliest anchor, keeping same day of month
    maxDate = new Date(Date.UTC(
      minAnchor.getUTCFullYear(),
      minAnchor.getUTCMonth() + endCondition.value,
      minAnchor.getUTCDate()
    ));
  } else if (endCondition.type === 'years') {
    // Add N years from earliest anchor, keeping same month and day
    maxDate = new Date(Date.UTC(
      minAnchor.getUTCFullYear() + endCondition.value,
      minAnchor.getUTCMonth(),
      minAnchor.getUTCDate()
    ));
  } else {
    // Specific end date - use the exact date, not end of month
    maxDate = parseDateAsUTC(endCondition.date);
  }

  return {
    minMonth: new Date(Date.UTC(minAnchor.getUTCFullYear(), minAnchor.getUTCMonth(), 1)),
    maxMonth: new Date(Date.UTC(maxDate.getUTCFullYear(), maxDate.getUTCMonth(), 1)),
    maxDate,
  };
}

/**
 * Generate virtual shift occurrences for a specific month
 *
 * @param yearMonth - Target month (e.g., { year: 2025, month: 10 })
 * @param draft - Recurring draft with anchors, interval, and end condition
 * @returns Array of virtual shift occurrences in the target month
 *
 * @example
 * generateVirtualShiftsForMonth({ year: 2025, month: 11 }, draft)
 * // Returns virtual shifts for November 2025 based on anchors and interval
 */
export function generateVirtualShiftsForMonth(
  yearMonth: { year: number; month: number },
  draft: RecurringDraft
): RecurringVirtualShift[] {
  const { selected_days, repeat_interval_weeks, end_condition, exclusions } = draft;

  if (Object.keys(selected_days).length === 0) return [];

  const monthStart = parseDateAsUTC(getMonthStart(yearMonth.year, yearMonth.month));
  const monthEnd = parseDateAsUTC(getMonthEnd(yearMonth.year, yearMonth.month));

  // Get the end window to check if we're past the recurring shift end
  // For infinite recurring shifts (end_condition === null), we don't need a window check
  const window = end_condition !== null ? resolveEndWindow(selected_days, end_condition) : null;

  const virtualShifts: RecurringVirtualShift[] = [];
  const exclusionSet = new Set(exclusions);

  // For each selected weekday anchor
  for (const [weekdayKey, anchorISO] of Object.entries(selected_days)) {
    const weekday = Number(weekdayKey); // 0 (Sun) through 6 (Sat)

    // Find first occurrence of this weekday in the target month
    let current = new Date(monthStart);
    const currentWeekday = current.getUTCDay();
    const daysUntilTarget = (weekday - currentWeekday + 7) % 7;
    current.setUTCDate(current.getUTCDate() + daysUntilTarget);

    // If we're before the month start, move to next week
    if (current < monthStart) {
      current.setUTCDate(current.getUTCDate() + 7);
    }

    // Generate occurrences for this weekday throughout the month
    while (current <= monthEnd) {
      const currentISO = toISODate(current);

      // Check if this date is on or after the anchor date (virtual shifts should only go forwards in time)
      const anchorDate = new Date(anchorISO + 'T00:00:00Z');
      if (current < anchorDate) {
        current.setUTCDate(current.getUTCDate() + 7);
        continue;
      }

      // Check if this date is in phase with the anchor
      const inPhase = isInPhase(currentISO, anchorISO, repeat_interval_weeks);

      // Check if within the recurring shift window (only enforce if there's an end condition)
      const withinWindow = window === null || (current >= window.minMonth && current <= window.maxDate);

      // Check if not excluded
      const notExcluded = !exclusionSet.has(currentISO);

      if (inPhase && withinWindow && notExcluded) {
        virtualShifts.push({
          date: currentISO,
          weekday,
          // Earnings will be calculated separately by the calendar component
        });
      }

      // Move to next week
      current.setUTCDate(current.getUTCDate() + 7);
    }
  }

  return virtualShifts.sort((a, b) => a.date.localeCompare(b.date));
}

/**
 * Check if a date should be disabled in the calendar
 *
 * @param dateISO - ISO date to check
 * @param draft - Recurring draft
 * @param window - Date window (from resolveEndWindow)
 * @returns true if date should be disabled
 */
export function isDateDisabled(
  dateISO: string,
  draft: RecurringDraft,
  window: DateWindow
): boolean {
  const date = parseDateAsUTC(dateISO);

  // 1) Outside navigable window?
  if (date < window.minMonth || date > window.maxMonth) {
    return true;
  }

  // 2) Already selected (same weekday)?
  const weekdayKey = getWeekdayKey(date);
  const hasSameWeekday = draft.selected_days[weekdayKey] !== undefined;

  if (hasSameWeekday) {
    // Allow clicking on the existing anchor to update it
    return draft.selected_days[weekdayKey] !== dateISO;
  }

  // 3) Already have 7 weekdays selected?
  const selectedCount = Object.keys(draft.selected_days).length;
  if (selectedCount >= 7) {
    return true;
  }

  return false;
}

/**
 * Format weekday name for display
 *
 * @param weekdayKey - Weekday key ('0' through '6')
 * @param locale - Locale code
 * @returns Human-readable weekday name
 */
export function formatWeekdayName(
  weekdayKey: '0' | '1' | '2' | '3' | '4' | '5' | '6',
  locale: string = 'en'
): string {
  const namesEn = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const namesNo = ['Søndag', 'Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag'];

  const names = locale === 'no' ? namesNo : namesEn;
  return names[Number(weekdayKey)];
}

/**
 * Format short weekday name for chips
 *
 * @param weekdayKey - Weekday key ('0' through '6')
 * @param locale - Locale code
 * @returns Short weekday abbreviation
 */
export function formatWeekdayShort(
  weekdayKey: '0' | '1' | '2' | '3' | '4' | '5' | '6',
  locale: string = 'en'
): string {
  const shortEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const shortNo = ['Søn', 'Man', 'Tir', 'Ons', 'Tor', 'Fre', 'Lør'];

  const shorts = locale === 'no' ? shortNo : shortEn;
  return shorts[Number(weekdayKey)];
}
