import { generateVirtualShiftsForMonth } from "../_shared/wagey/recurring/utils.ts";
import { compareISODate, monthsBetweenInclusive } from "./date.ts";
import type {
  CalendarData,
  CalendarEventRow,
  CalendarJobRow,
  CalendarRecurringShiftRow,
  CalendarShiftRow,
  CalendarSubscriptionContentMode,
  CalendarSupabaseClient,
  FeedWindow,
  ProjectedRecurringShift,
} from "./types.ts";

const SHIFT_SELECT =
  "id, shift_date, start_time, end_time, note, job_id, updated_at";
const RECURRING_SHIFT_SELECT =
  "id, start_time, end_time, repeat_interval_weeks, selected_days, end_condition, exclusions, date_specific_notes, job_id, updated_at";
const JOB_SELECT = "id, name";
const EVENT_SELECT =
  "id, start_date, end_date, is_all_day, start_time, end_time, note, updated_at";

type QueryResult<T> = {
  data: T[] | null;
  error: { message?: string } | null;
};

function includesShifts(contentMode: CalendarSubscriptionContentMode): boolean {
  return contentMode === "shifts_only" || contentMode === "shifts_and_events";
}

function includesEvents(contentMode: CalendarSubscriptionContentMode): boolean {
  return contentMode === "events_only" || contentMode === "shifts_and_events";
}

async function runQuery<T>(query: unknown): Promise<T[]> {
  const result = await query as QueryResult<T>;
  if (result.error) {
    throw new Error(result.error.message ?? "Calendar feed query failed");
  }
  return result.data ?? [];
}

export async function loadCalendarData(
  supabase: CalendarSupabaseClient,
  userId: string,
  contentMode: CalendarSubscriptionContentMode,
  window: FeedWindow,
): Promise<CalendarData> {
  const shiftsPromise = includesShifts(contentMode)
    ? runQuery<CalendarShiftRow>(
      // deno-lint-ignore no-explicit-any
      (supabase.from("user_shifts") as any)
        .select(SHIFT_SELECT)
        .eq("user_id", userId)
        .is("deleted_at", null)
        .gte("shift_date", window.startDate)
        .lte("shift_date", window.endDate)
        .order("shift_date", { ascending: true }),
    )
    : Promise.resolve([]);

  const recurringPromise = includesShifts(contentMode)
    ? runQuery<CalendarRecurringShiftRow>(
      // deno-lint-ignore no-explicit-any
      (supabase.from("recurring_shifts") as any)
        .select(RECURRING_SHIFT_SELECT)
        .eq("user_id", userId)
        .is("deleted_at", null),
    )
    : Promise.resolve([]);

  const jobsPromise = includesShifts(contentMode)
    ? runQuery<CalendarJobRow>(
      // deno-lint-ignore no-explicit-any
      (supabase.from("jobs") as any)
        .select(JOB_SELECT)
        .eq("user_id", userId)
        .is("deleted_at", null),
    )
    : Promise.resolve([]);

  const eventsPromise = includesEvents(contentMode)
    ? runQuery<CalendarEventRow>(
      // deno-lint-ignore no-explicit-any
      (supabase.from("events") as any)
        .select(EVENT_SELECT)
        .eq("user_id", userId)
        .is("deleted_at", null)
        .gte("end_date", window.startDate)
        .lte("start_date", window.endDate)
        .order("start_date", { ascending: true })
        .order("end_date", { ascending: true })
        .order("start_time", { ascending: true, nullsFirst: true }),
    )
    : Promise.resolve([]);

  const [shifts, recurringShifts, jobs, events] = await Promise.all([
    shiftsPromise,
    recurringPromise,
    jobsPromise,
    eventsPromise,
  ]);

  return { shifts, recurringShifts, jobs, events };
}

export function projectRecurringShifts(
  recurringShifts: CalendarRecurringShiftRow[],
  window: FeedWindow,
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
