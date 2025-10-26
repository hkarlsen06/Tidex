import "server-only";
import { cache } from "react";
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
 * Get computed shifts with pagination and caching
 * - Uses React cache() for request deduplication within a single request
 * - Supports date range filtering and limits
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

  // Compute aggregates once on the server
  const aggregates: ShiftsAggregates = computedShifts.reduce(
    (acc, shift) => ({
      totalHours: acc.totalHours + shift.computed.paidHours,
      totalEarnings: acc.totalEarnings + shift.computed.gross,
    }),
    { totalHours: 0, totalEarnings: 0 }
  );

  return {
    shifts: computedShifts,
    defaultView: (settingsRow as any)?.default_shifts_view || "calendar",
    settings,
    aggregates
  };
});
