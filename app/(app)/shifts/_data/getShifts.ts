import "server-only";
import { cache } from "react";
import { unstable_cache } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  computeShift,
  type ShiftRow,
  type ShiftWithComputations,
  type UserSettings,
  PRESET_SUPPLEMENT_RULES,
} from "@/lib/payroll";
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
 * Helper to get date N months ago in YYYY-MM-DD format
 */
function getMonthsAgo(months: number): string {
  const date = new Date();
  date.setUTCMonth(date.getUTCMonth() - months);
  date.setUTCDate(1); // Start of month
  return date.toISOString().split('T')[0];
}

/**
 * Helper to get current date in YYYY-MM-DD format
 */
function getCurrentDate(): string {
  return new Date().toISOString().split('T')[0];
}

/**
 * Internal implementation of getComputedShifts
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
    startDate = getMonthsAgo(6), // Default: last 6 months
    endDate = getCurrentDate(),
    limit = 500
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
}

/**
 * Get computed shifts with pagination and caching
 * - Uses React cache() for request deduplication
 * - Uses Next.js Data Cache for persistent caching (5 min TTL)
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
  // Resolve defaults to ensure consistent cache keys
  const resolvedOptions = {
    startDate: options.startDate ?? getMonthsAgo(6),
    endDate: options.endDate ?? getCurrentDate(),
    limit: options.limit ?? 500
  };

  // Create a cache key based on resolved options
  const cacheKey = `shifts-${userId}-${resolvedOptions.startDate}-${resolvedOptions.endDate}-${resolvedOptions.limit}`;

  // Wrap with unstable_cache for persistent caching
  const getCached = unstable_cache(
    async () => getComputedShiftsInternal(userId, options),
    [cacheKey],
    {
      tags: [`user-shifts-${userId}`],
      revalidate: 300 // 5 minutes
    }
  );

  return getCached();
});
