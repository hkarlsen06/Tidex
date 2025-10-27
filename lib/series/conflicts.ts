/**
 * Conflict detection for series shifts
 *
 * Checks if projected ghost occurrences would overlap with existing shifts
 * Handles cross-midnight shifts correctly
 */

import type { SeriesGhost, SeriesDraft } from './types';

/**
 * Existing shift shape (minimal data needed for conflict detection)
 */
export type ExistingShift = {
  shift_date: string; // YYYY-MM-DD
  start_time: string; // HH:mm
  end_time: string; // HH:mm
};

/**
 * Convert HH:mm time to minutes since midnight
 */
function timeToMinutes(time: string): number {
  const [hours, minutes] = time.split(':').map(Number);
  return hours * 60 + minutes;
}

/**
 * Add days to an ISO date string
 */
function addDaysToISO(iso: string, days: number): string {
  const date = new Date(iso + 'T00:00:00Z');
  date.setUTCDate(date.getUTCDate() + days);
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Check if two time ranges overlap
 *
 * @param start1 - Start time in minutes
 * @param end1 - End time in minutes
 * @param start2 - Start time in minutes
 * @param end2 - End time in minutes
 * @returns true if the ranges overlap
 */
function timeRangesOverlap(
  start1: number,
  end1: number,
  start2: number,
  end2: number
): boolean {
  return start1 < end2 && start2 < end1;
}

/**
 * Build an interval map from existing shifts
 * Expands cross-midnight shifts to cover both days
 *
 * @param existingShifts - Array of existing shifts
 * @returns Map of ISO date to array of [startMin, endMin] intervals
 */
export function buildIntervalMap(
  existingShifts: ExistingShift[]
): Map<string, Array<[number, number]>> {
  const map = new Map<string, Array<[number, number]>>();

  for (const shift of existingShifts) {
    const startMin = timeToMinutes(shift.start_time);
    const endMin = timeToMinutes(shift.end_time);

    if (endMin > startMin) {
      // Normal shift (same day)
      const intervals = map.get(shift.shift_date) ?? [];
      intervals.push([startMin, endMin]);
      map.set(shift.shift_date, intervals);
    } else {
      // Cross-midnight shift
      // Part 1: from start_time to end of day
      const intervals1 = map.get(shift.shift_date) ?? [];
      intervals1.push([startMin, 24 * 60]);
      map.set(shift.shift_date, intervals1);

      // Part 2: from start of next day to end_time
      const nextDay = addDaysToISO(shift.shift_date, 1);
      const intervals2 = map.get(nextDay) ?? [];
      intervals2.push([0, endMin]);
      map.set(nextDay, intervals2);
    }
  }

  return map;
}

/**
 * Detect conflicts between ghosts and existing shifts
 *
 * @param ghosts - Array of projected ghost occurrences
 * @param existingShifts - Array of existing shifts
 * @param startTime - Ghost start time (HH:mm)
 * @param endTime - Ghost end time (HH:mm)
 * @returns Map of ghost date to array of conflicting shifts
 */
export function detectConflicts(
  ghosts: SeriesGhost[],
  existingShifts: ExistingShift[],
  startTime: string,
  endTime: string
): Map<string, ExistingShift[]> {
  const conflicts = new Map<string, ExistingShift[]>();
  const intervalMap = buildIntervalMap(existingShifts);

  const ghostStartMin = timeToMinutes(startTime);
  const ghostEndMin = timeToMinutes(endTime);
  const isCrossMidnight = ghostEndMin <= ghostStartMin;

  for (const ghost of ghosts) {
    const conflictingShifts: ExistingShift[] = [];

    if (!isCrossMidnight) {
      // Normal ghost shift (same day)
      const intervals = intervalMap.get(ghost.date);
      if (intervals) {
        for (const [start, end] of intervals) {
          if (timeRangesOverlap(start, end, ghostStartMin, ghostEndMin)) {
            // Find which shift this interval belongs to
            const shift = existingShifts.find(
              (s) =>
                s.shift_date === ghost.date &&
                timeToMinutes(s.start_time) === start &&
                (timeToMinutes(s.end_time) === end ||
                  // Handle cross-midnight case where end might be 1440
                  (end === 24 * 60 && timeToMinutes(s.end_time) < start))
            );
            if (shift && !conflictingShifts.includes(shift)) {
              conflictingShifts.push(shift);
            }
          }
        }
      }
    } else {
      // Cross-midnight ghost shift
      // Check conflicts on ghost date (from start_time to midnight)
      const intervals1 = intervalMap.get(ghost.date);
      if (intervals1) {
        for (const [start, end] of intervals1) {
          if (timeRangesOverlap(start, end, ghostStartMin, 24 * 60)) {
            const shift = existingShifts.find(
              (s) =>
                s.shift_date === ghost.date &&
                timeToMinutes(s.start_time) === start
            );
            if (shift && !conflictingShifts.includes(shift)) {
              conflictingShifts.push(shift);
            }
          }
        }
      }

      // Check conflicts on next day (from midnight to end_time)
      const nextDay = addDaysToISO(ghost.date, 1);
      const intervals2 = intervalMap.get(nextDay);
      if (intervals2) {
        for (const [start, end] of intervals2) {
          if (timeRangesOverlap(start, end, 0, ghostEndMin)) {
            const shift = existingShifts.find(
              (s) =>
                (s.shift_date === nextDay && timeToMinutes(s.start_time) === start) ||
                (s.shift_date === ghost.date &&
                  timeToMinutes(s.end_time) < timeToMinutes(s.start_time))
            );
            if (shift && !conflictingShifts.includes(shift)) {
              conflictingShifts.push(shift);
            }
          }
        }
      }
    }

    if (conflictingShifts.length > 0) {
      conflicts.set(ghost.date, conflictingShifts);
    }
  }

  return conflicts;
}

/**
 * Build a set of conflict dates (ISO strings) for easy lookup
 *
 * @param conflicts - Conflict map from detectConflicts()
 * @returns Set of ISO dates that have conflicts
 */
export function buildConflictDateSet(
  conflicts: Map<string, ExistingShift[]>
): Set<string> {
  return new Set(conflicts.keys());
}

/**
 * Detect all conflicts across the entire series duration
 * Generates ghosts for all months and checks each for conflicts
 *
 * @param draft - Series draft with anchor dates and time range
 * @param existingShifts - Array of all user's existing shifts
 * @returns Array of ISO date strings that have conflicts
 */
export async function detectAllSeriesConflicts(
  draft: SeriesDraft,
  existingShifts: ExistingShift[]
): Promise<string[]> {
  // Import needed utilities
  const { generateGhostsForMonth, resolveEndWindow } = await import('./utils');

  if (Object.keys(draft.selected_days).length === 0) return [];

  // Determine the date range to check
  const window = draft.end_condition !== null
    ? resolveEndWindow(draft.selected_days, draft.end_condition)
    : null;

  const allConflictDates = new Set<string>();

  // If infinite series, check a reasonable window (e.g., 5 years)
  const currentYear = new Date().getUTCFullYear();
  const currentMonth = new Date().getUTCMonth() + 1;

  let startYear: number, startMonth: number, endYear: number, endMonth: number;

  if (window) {
    startYear = window.minMonth.getUTCFullYear();
    startMonth = window.minMonth.getUTCMonth() + 1;
    endYear = window.maxMonth.getUTCFullYear();
    endMonth = window.maxMonth.getUTCMonth() + 1;
  } else {
    // For infinite series, check 5 years ahead
    startYear = currentYear;
    startMonth = currentMonth;
    endYear = currentYear + 5;
    endMonth = 12;
  }

  // Generate ghosts for each month and detect conflicts
  for (let year = startYear; year <= endYear; year++) {
    const startM = (year === startYear) ? startMonth : 1;
    const endM = (year === endYear) ? endMonth : 12;

    for (let month = startM; month <= endM; month++) {
      const ghosts = generateGhostsForMonth({ year, month }, draft);

      if (ghosts.length > 0) {
        const monthConflicts = detectConflicts(
          ghosts,
          existingShifts,
          draft.start_time,
          draft.end_time
        );

        // Add all conflict dates to the set
        for (const date of Array.from(monthConflicts.keys())) {
          allConflictDates.add(date);
        }
      }
    }
  }

  return Array.from(allConflictDates).sort();
}
