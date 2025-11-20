/**
 * Shifts Service Layer
 *
 * Effect-based service for shift data access with:
 * - Parallel query execution for shifts and series
 * - Automatic snapshot resolution
 * - Type-safe error handling
 * - Caching for performance
 *
 * Usage:
 * ```typescript
 * const program = Effect.gen(function* () {
 *   const shifts = yield* ShiftsService
 *   const data = yield* shifts.getShiftsWithComputations({
 *     userId,
 *     startDate: "2025-01-01",
 *     endDate: "2025-01-31"
 *   })
 *   return data
 * }).pipe(
 *   Effect.provide(ShiftsServiceLive)
 * )
 * ```
 */

import "server-only";
import { Context, Effect, Layer } from "effect";
import { AuthService } from "./auth";
import { SupabaseService } from "./supabase";
import { SettingsService, type DbUserSettings } from "./settings";
import { DatabaseError, AuthError, NotFoundError, TimeoutError, SupabaseError } from "../errors/tagged";
import {
  computeShift,
  type ShiftRow,
  type ShiftWithComputations,
  type UserSettings,
  PRESET_SUPPLEMENT_RULES,
  type WageSnapshot,
} from "../payroll";
import { getCurrentYearMonth, getMonthStart, getMonthEnd } from "../date-utils";
import { generateGhostsForMonth } from "../series/utils";
import type { SeriesShiftRow } from "../series/types";
import { cleanTime } from "../time-utils";

/**
 * Shift load options for filtering and pagination
 */
export type ShiftLoadOptions = {
  readonly userId: string;
  readonly startDate?: string; // YYYY-MM-DD
  readonly endDate?: string; // YYYY-MM-DD
  readonly limit?: number;
};

/**
 * Aggregated shift statistics
 */
export type ShiftsAggregates = {
  readonly totalHours: number;
  readonly totalEarnings: number;
};

/**
 * Complete shift data response
 */
export type ShiftData = {
  readonly shifts: readonly ShiftWithComputations[];
  readonly defaultView: string;
  readonly settings: UserSettings;
  readonly aggregates: ShiftsAggregates;
};

/**
 * Database series shift row
 */
type DbSeriesShift = SeriesShiftRow & {
  user_id: string;
};

/**
 * Shifts Service Interface
 */
export class ShiftsService extends Context.Tag("ShiftsService")<
  ShiftsService,
  {
    /**
     * Get shifts with computations, series ghosts, and aggregates
     * Automatically verifies user authentication
     */
    readonly getShiftsWithComputations: (
      options: ShiftLoadOptions
    ) => Effect.Effect<
      ShiftData,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get wage snapshots for multiple shift dates (batch lookup)
     * Returns a Map of shift date to applicable WageSnapshot
     */
    readonly getSnapshotsForDates: (
      userId: string,
      dates: readonly string[]
    ) => Effect.Effect<
      ReadonlyMap<string, WageSnapshot>,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;
  }
>() {}

/**
 * Live implementation of ShiftsService
 *
 * Provides parallel query execution and efficient snapshot resolution
 */
export const ShiftsServiceLive = Layer.effect(
  ShiftsService,
  Effect.gen(function* () {
    const auth = yield* AuthService;
    const supabase = yield* SupabaseService;
    const settings = yield* SettingsService;

    /**
     * Get default start date (current month start)
     */
    const getDefaultStartDate = (): string => {
      const { year, month } = getCurrentYearMonth();
      return getMonthStart(year, month);
    };

    /**
     * Get default end date (current month end)
     */
    const getDefaultEndDate = (): string => {
      const { year, month } = getCurrentYearMonth();
      return getMonthEnd(year, month);
    };

    /**
     * Get wage snapshots for user (all snapshots, ordered by from_date DESC)
     */
    const getUserWageSnapshots = (userId: string) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        const snapshots = yield* supabase.query(
          async (client) =>
            await client
              .from("wage_snapshots")
              .select("*")
              .eq("user_id", userId)
              .order("from_date", { ascending: false, nullsFirst: false }),
          { retries: 2 }
        );

        return (snapshots ?? []) as WageSnapshot[];
      });

    /**
     * Get snapshots for multiple dates (batch lookup)
     */
    const getSnapshotsForDates = (userId: string, dates: readonly string[]) =>
      Effect.gen(function* () {
        const snapshots = yield* getUserWageSnapshots(userId);
        const snapshotMap = new Map<string, WageSnapshot>();

        // Find baseline snapshot once for fallback
        const baselineSnapshot = snapshots.find((s) => s.from_date === null);

        for (const shiftDate of dates) {
          // Find the first dated snapshot where from_date <= shiftDate
          const applicableSnapshot = snapshots.find(
            (s) => s.from_date !== null && s.from_date <= shiftDate
          );

          // Use dated snapshot if found, otherwise fall back to baseline
          const snapshotToUse = applicableSnapshot || baselineSnapshot;

          if (snapshotToUse) {
            snapshotMap.set(shiftDate, snapshotToUse);
          }
        }

        return snapshotMap as ReadonlyMap<string, WageSnapshot>;
      });

    /**
     * Get shifts with computations
     */
    const getShiftsWithComputations = (options: ShiftLoadOptions) =>
      Effect.gen(function* () {
        const {
          userId,
          startDate = getDefaultStartDate(),
          endDate = getDefaultEndDate(),
          limit = 50,
        } = options;

        // Verify authentication
        yield* auth.verifyUserId(userId);

        // Fetch user settings
        const userSettingsResult = yield* settings.getUserSettings(userId);
        const userSettings: UserSettings = (userSettingsResult as any) ?? {};

        // Build query with filters
        const shiftsQuery = async (client: any) => {
          let query = client
            .from("user_shifts")
            .select("*")
            .eq("user_id", userId)
            .order("shift_date", { ascending: false });

          if (startDate) {
            query = query.gte("shift_date", startDate);
          }
          if (endDate) {
            query = query.lte("shift_date", endDate);
          }
          if (limit) {
            query = query.limit(limit);
          }

          return await query;
        };

        // Fetch series shifts
        const seriesQuery = async (client: any) =>
          await client
            .from("series_shifts")
            .select("*")
            .eq("user_id", userId);

        // Execute queries in parallel
        const [shifts, seriesShifts] = yield* Effect.all(
          [
            supabase.query(shiftsQuery, { retries: 2 }),
            supabase.query(seriesQuery, { retries: 2 }),
          ],
          { concurrency: 2 }
        );

        // Collect all shift dates for batch snapshot lookup
        const shiftDates = (shifts ?? []).map((s: ShiftRow) => s.shift_date);

        // Generate series ghosts and collect their dates
        const ghostDates: string[] = [];
        const startYear = new Date(startDate).getFullYear();
        const startMonth = new Date(startDate).getMonth() + 1;
        const endYear = new Date(endDate).getFullYear();
        const endMonth = new Date(endDate).getMonth() + 1;

        for (const series of (seriesShifts ?? []) as DbSeriesShift[]) {
          let currentYear = startYear;
          let currentMonth = startMonth;

          while (
            currentYear < endYear ||
            (currentYear === endYear && currentMonth <= endMonth)
          ) {
            const ghosts = generateGhostsForMonth(
              { year: currentYear, month: currentMonth },
              {
                start_time: cleanTime(series.start_time),
                end_time: cleanTime(series.end_time),
                repeat_interval_weeks: series.repeat_interval_weeks as
                  | 0
                  | 1
                  | 2
                  | 3
                  | 4
                  | 5
                  | 6
                  | 7
                  | 8,
                selected_days: series.selected_days,
                end_condition: series.end_condition,
                exclusions: series.exclusions || [],
              }
            );

            ghostDates.push(...ghosts.map((g) => g.date));

            // Move to next month
            currentMonth++;
            if (currentMonth > 12) {
              currentMonth = 1;
              currentYear++;
            }
          }
        }

        // Fetch snapshots for all dates (shifts + ghosts) in one batch
        const allDates = [...shiftDates, ...ghostDates];
        const snapshotMap = yield* getSnapshotsForDates(userId, allDates);

        // Compute regular shifts
        const computedShifts = ((shifts ?? []) as ShiftRow[]).map((shift) => {
          const snapshot = snapshotMap.get(shift.shift_date) ?? null;
          return {
            ...shift,
            computed: computeShift(shift, userSettings, PRESET_SUPPLEMENT_RULES, snapshot),
          };
        });

        // Compute series ghosts
        const seriesGhosts: ShiftWithComputations[] = [];
        for (const series of (seriesShifts ?? []) as DbSeriesShift[]) {
          let currentYear = startYear;
          let currentMonth = startMonth;

          while (
            currentYear < endYear ||
            (currentYear === endYear && currentMonth <= endMonth)
          ) {
            const ghosts = generateGhostsForMonth(
              { year: currentYear, month: currentMonth },
              {
                start_time: cleanTime(series.start_time),
                end_time: cleanTime(series.end_time),
                repeat_interval_weeks: series.repeat_interval_weeks as
                  | 0
                  | 1
                  | 2
                  | 3
                  | 4
                  | 5
                  | 6
                  | 7
                  | 8,
                selected_days: series.selected_days,
                end_condition: series.end_condition,
                exclusions: series.exclusions || [],
              }
            );

            for (const ghost of ghosts) {
              const snapshot = snapshotMap.get(ghost.date) ?? null;
              const computed = computeShift(
                {
                  id: `ghost-${series.id}-${ghost.date}`,
                  user_id: userId,
                  shift_date: ghost.date,
                  start_time: cleanTime(series.start_time),
                  end_time: cleanTime(series.end_time),
                  series_id: series.id,
                  series_anchor_weekday: ghost.weekday,
                },
                userSettings,
                PRESET_SUPPLEMENT_RULES,
                snapshot
              );

              seriesGhosts.push({
                id: `ghost-${series.id}-${ghost.date}`,
                user_id: userId,
                shift_date: ghost.date,
                start_time: cleanTime(series.start_time),
                end_time: cleanTime(series.end_time),
                series_id: series.id,
                series_anchor_weekday: ghost.weekday,
                computed,
              });
            }

            // Move to next month
            currentMonth++;
            if (currentMonth > 12) {
              currentMonth = 1;
              currentYear++;
            }
          }
        }

        // Merge shifts and series ghosts
        const allShifts = [...computedShifts, ...seriesGhosts];

        // Compute aggregates
        const aggregates: ShiftsAggregates = allShifts.reduce(
          (acc, shift) => ({
            totalHours: acc.totalHours + shift.computed.paidHours,
            totalEarnings: acc.totalEarnings + shift.computed.gross,
          }),
          { totalHours: 0, totalEarnings: 0 }
        );

        return {
          shifts: allShifts as readonly ShiftWithComputations[],
          defaultView: (userSettingsResult as DbUserSettings)?.default_shifts_view || "calendar",
          settings: userSettings,
          aggregates,
        };
      });

    return {
      getShiftsWithComputations,
      getSnapshotsForDates,
    };
  })
);

/**
 * Convenience function to provide ShiftsServiceLive with dependencies
 */
export const withShifts = <A, E, R>(
  effect: Effect.Effect<A, E, R | ShiftsService>
): Effect.Effect<
  A,
  E,
  Exclude<R, ShiftsService> | AuthService | SupabaseService | SettingsService
> => Effect.provide(effect, ShiftsServiceLive);
