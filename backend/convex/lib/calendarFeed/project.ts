import { generateVirtualShiftsForMonth } from "../shared/recurring/utils";
import { compareISODate, monthsBetweenInclusive } from "./date";
import type { CalendarRecurringShiftRow, CalendarShiftRow, FeedWindow, ProjectedRecurringShift } from "./types";

// projectRecurringShifts from supabase/functions/calendar-feed/data.ts, unchanged.

export function projectRecurringShifts(
  recurringShifts: CalendarRecurringShiftRow[],
  window: FeedWindow,
  _materializedShifts: CalendarShiftRow[] = [],
): ProjectedRecurringShift[] {
  const projected: ProjectedRecurringShift[] = [];

  for (const recurringShift of recurringShifts) {
    for (const yearMonth of monthsBetweenInclusive(window)) {
      const occurrences = generateVirtualShiftsForMonth(yearMonth, {
        start_time: recurringShift.start_time,
        end_time: recurringShift.end_time,
        repeat_interval_weeks: recurringShift.repeat_interval_weeks as
          | 0
          | 1
          | 2
          | 3
          | 4
          | 5
          | 6
          | 7
          | 8,
        selected_days: recurringShift.selected_days,
        end_condition: recurringShift.end_condition,
        exclusions: recurringShift.exclusions ?? [],
      });

      for (const occurrence of occurrences) {
        if (
          compareISODate(occurrence.date, window.startDate) < 0 ||
          compareISODate(occurrence.date, window.endDate) > 0
        ) {
          continue;
        }

        projected.push({
          id: recurringShift.id,
          occurrenceDate: occurrence.date,
          start_time: recurringShift.start_time,
          end_time: recurringShift.end_time,
          note: recurringShift.date_specific_notes?.[occurrence.date] ?? null,
          job_id: recurringShift.job_id,
          updated_at: recurringShift.updated_at,
        });
      }
    }
  }

  return projected.sort((left, right) =>
    compareISODate(left.occurrenceDate, right.occurrenceDate) ||
    left.id.localeCompare(right.id)
  );
}
