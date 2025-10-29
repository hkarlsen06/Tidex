import "server-only";
import { cache } from "react";
import { verifySession } from "@/data-access/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  computeShift,
  type ShiftRow,
  type ShiftWithComputations,
  type UserSettings,
  PRESET_SUPPLEMENT_RULES,
} from "@/lib/payroll";
import { getCurrentYearMonth, getMonthStart, getMonthEnd } from "@/lib/date-utils";
import { logger } from "@/lib/logger";
import { generateGhostsForMonth } from "@/lib/series/utils";
import type { SeriesShiftRow } from "@/lib/series/types";
import { cleanTime } from "@/lib/time-utils";

export const PRESET_RULES = PRESET_SUPPLEMENT_RULES;

export type ShiftsAggregates = {
  totalHours: number;
  totalEarnings: number;
};

export type ShiftLoadOptions = {
  startDate?: string; // YYYY-MM-DD
  endDate?: string; // YYYY-MM-DD
  limit?: number;
};

/**
 * Get default start date for shift loading (current month start)
 * Used when no explicit startDate is provided
 */
function getDefaultStartDate(): string {
  const { year, month } = getCurrentYearMonth();
  return getMonthStart(year, month);
}

/**
 * Get default end date for shift loading (current month end)
 * Used when no explicit endDate is provided
 */
function getDefaultEndDate(): string {
  const { year, month } = getCurrentYearMonth();
  return getMonthEnd(year, month);
}

/**
 * Internal implementation of getComputedShifts
 * @internal - Do not call directly, use getComputedShifts() or getComputedShiftsForApi()
 */
async function getComputedShiftsInternal(
  userId: string,
  options: ShiftLoadOptions = {}
): Promise<{
  shifts: ShiftWithComputations[],
  defaultView: string,
  settings: UserSettings,
  aggregates: ShiftsAggregates
}> {
  const {
    startDate = getDefaultStartDate(), // Default: current month start
    endDate = getDefaultEndDate(),     // Default: current month end
    limit = 50                          // Default: reasonable limit for 1 month
  } = options;

  const supabase = await createSupabaseServerClient();

  const { data: settingsRow, error: settingsErr } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (settingsErr && settingsErr.code !== "PGRST116") {
    logger.error("Failed to load user settings:", settingsErr);
    throw new Error("Kunne ikke laste brukerinnstillinger. Vennligst prøv igjen senere.");
  }
  const settings: UserSettings = settingsRow ?? {};

  let query = supabase
    .from("user_shifts")
    .select("*")
    .eq("user_id", userId)
    .order("shift_date", { ascending: false });

  // Apply date range filters
  if (startDate) {
    query = query.gte("shift_date", startDate);
  }
  if (endDate) {
    query = query.lte("shift_date", endDate);
  }
  if (limit) {
    query = query.limit(limit);
  }

  const { data: shifts, error: shiftsErr } = await query;

  if (shiftsErr) {
    logger.error("user_shifts error:", shiftsErr);
    return {
      shifts: [],
      defaultView: "calendar",
      settings,
      aggregates: { totalHours: 0, totalEarnings: 0 }
    };
  }

  const computedShifts = ((shifts ?? []) as ShiftRow[]).map((shift) => ({
    ...shift,
    computed: computeShift(shift, settings, PRESET_RULES),
  }));

  // Load series shifts and generate ghosts for the date range
  const { data: seriesShifts, error: seriesError } = await supabase
    .from("series_shifts")
    .select("*")
    .eq("user_id", userId);

  if (seriesError) {
    logger.error("Failed to load series shifts:", seriesError);
  }

  const seriesGhosts: ShiftWithComputations[] = [];
  if (seriesShifts && seriesShifts.length > 0) {
    // Generate ghosts for all months in the range
    const startYear = new Date(startDate).getFullYear();
    const startMonth = new Date(startDate).getMonth() + 1;
    const endYear = new Date(endDate).getFullYear();
    const endMonth = new Date(endDate).getMonth() + 1;

    for (const series of seriesShifts as SeriesShiftRow[]) {
      // Generate for each month in range
      let currentYear = startYear;
      let currentMonth = startMonth;

      while (
        currentYear < endYear ||
        (currentYear === endYear && currentMonth <= endMonth)
      ) {
        const ghosts = generateGhostsForMonth({ year: currentYear, month: currentMonth }, {
          start_time: cleanTime(series.start_time),
          end_time: cleanTime(series.end_time),
          repeat_interval_weeks: series.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8,
          selected_days: series.selected_days,
          end_condition: series.end_condition,
          exclusions: series.exclusions || []
        });

        // Compute each ghost
        for (const ghost of ghosts) {
          try {
            const computed = computeShift(
              {
                id: `ghost-${series.id}-${ghost.date}`,
                user_id: userId,
                shift_date: ghost.date,
                start_time: cleanTime(series.start_time),
                end_time: cleanTime(series.end_time),
                series_id: series.id,
                series_anchor_weekday: ghost.weekday
              },
              settings,
              PRESET_RULES
            );

            seriesGhosts.push({
              id: `ghost-${series.id}-${ghost.date}`,
              user_id: userId,
              shift_date: ghost.date,
              start_time: cleanTime(series.start_time),
              end_time: cleanTime(series.end_time),
              series_id: series.id,
              series_anchor_weekday: ghost.weekday,
              computed
            });
          } catch (err) {
            logger.error(`Failed to compute ghost for series ${series.id} on ${ghost.date}:`, err);
          }
        }

        // Move to next month
        currentMonth++;
        if (currentMonth > 12) {
          currentMonth = 1;
          currentYear++;
        }
      }
    }
  }

  // Merge shifts and series ghosts
  const allShifts = [...computedShifts, ...seriesGhosts];

  // Compute aggregates once on the server
  const aggregates: ShiftsAggregates = allShifts.reduce(
    (acc, shift) => ({
      totalHours: acc.totalHours + shift.computed.paidHours,
      totalEarnings: acc.totalEarnings + shift.computed.gross,
    }),
    { totalHours: 0, totalEarnings: 0 }
  );

  return {
    shifts: allShifts,
    defaultView: (settingsRow as any)?.default_shifts_view || "calendar",
    settings,
    aggregates
  };
}

/**
 * Get computed shifts with pagination and caching
 * - Uses React cache() for request deduplication within a single request
 * - Cache is scoped by userId to prevent cross-user data leaks
 * - Supports date range filtering and limits
 * - Automatically verifies user session matches provided userId
 * - Use this in Server Components and Server Actions
 */
export const getComputedShifts = cache(async (
  userId: string,
  options: ShiftLoadOptions = {}
): Promise<{
  shifts: ShiftWithComputations[],
  defaultView: string,
  settings: UserSettings,
  aggregates: ShiftsAggregates
}> => {
  const { user } = await verifySession();

  // SECURITY: Verify the provided userId matches the authenticated user
  if (user.id !== userId) {
    throw new Error('User ID mismatch - potential security violation');
  }

  return getComputedShiftsInternal(user.id, options);
});

/**
 * Get computed shifts for API routes (no automatic auth)
 * - Requires manual authentication before calling
 * - Use this in API route handlers where redirect() is not supported
 * - Call getSession() first to verify auth, then pass user.id
 */
export const getComputedShiftsForApi = cache(async (
  userId: string,
  options: ShiftLoadOptions = {}
): Promise<{
  shifts: ShiftWithComputations[],
  defaultView: string,
  settings: UserSettings,
  aggregates: ShiftsAggregates
}> => {
  return getComputedShiftsInternal(userId, options);
});
