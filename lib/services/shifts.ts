/**
 * Shifts Service Layer
 *
 * Effect-based service for shift data access with:
 * - Parallel query execution for shifts and recurring shifts
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
import { generateVirtualShiftsForMonth } from "../recurring/utils";
import type { RecurringShiftRow } from "../recurring/types";
import { cleanTime } from "../time-utils";

/**
 * Shift load options for filtering and pagination
 */
export type ShiftLoadOptions = {
  readonly userId: string;
  readonly startDate?: string; // YYYY-MM-DD
  readonly endDate?: string; // YYYY-MM-DD
  readonly limit?: number;
  /**
   * Skip user authentication check.
   * ONLY use this when access has already been verified (e.g., shared shifts via RLS).
   * @internal
   */
  readonly skipAuthCheck?: boolean;
  /**
   * Year of the earnings month for payout tax calculation.
   * When both year and month are provided, the service will fetch
   * the tax settings from the payout month's snapshot.
   */
  readonly year?: number;
  /**
   * Month (1-12) of the earnings month for payout tax calculation.
   * When both year and month are provided, the service will fetch
   * the tax settings from the payout month's snapshot.
   */
  readonly month?: number;
};

/**
 * Payout tax settings from the payout month's snapshot.
 * Used for calculating after-tax monthly totals.
 */
export type PayoutTaxSettings = {
  readonly enabled: boolean;
  readonly percentage: number;
} | null;

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
  /**
   * Tax settings from the payout month's snapshot.
   * Used for calculating after-tax monthly totals.
   * Only present when year and month are provided in options.
   */
  readonly payoutTaxSettings: PayoutTaxSettings;
};

/**
 * Database recurring shift row
 */
type DbRecurringShift = RecurringShiftRow & {
  user_id: string;
};

/**
 * Shifts Service Interface
 */
export class ShiftsService extends Context.Tag("ShiftsService")<
  ShiftsService,
  {
    /**
     * Get shifts with computations, recurring virtual shifts, and aggregates
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
     * Calculate the payout date for a given earnings month.
     * Payout is in the month after earnings, on the user's payroll_day.
     */
    const calculatePayoutDate = (
      earningsYear: number,
      earningsMonth: number, // 1-12
      payrollDay: number
    ): string => {
      // Payout month is earnings month + 1
      let payoutYear = earningsYear;
      let payoutMonth = earningsMonth + 1;

      if (payoutMonth > 12) {
        payoutMonth = 1;
        payoutYear += 1;
      }

      // Handle edge case: payroll_day exceeds days in payout month
      const daysInPayoutMonth = new Date(payoutYear, payoutMonth, 0).getDate();
      const effectivePayrollDay = Math.min(payrollDay, daysInPayoutMonth);

      return `${payoutYear}-${String(payoutMonth).padStart(2, '0')}-${String(effectivePayrollDay).padStart(2, '0')}`;
    };

    /**
     * Get wage snapshots for user (all snapshots, ordered by from_date DESC)
     * @param skipAuthCheck - Skip authentication when true (for shared access via RLS)
     */
    const getUserWageSnapshots = (userId: string, skipAuthCheck = false) =>
      Effect.gen(function* () {
        if (!skipAuthCheck) {
          yield* auth.verifyUserId(userId);
        }

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
     * Uses binary search for O(log n) lookup per date instead of O(n)
     * @param skipAuthCheck - Skip authentication when true (for shared access via RLS)
     */
    const getSnapshotsForDates = (userId: string, dates: readonly string[], skipAuthCheck = false) =>
      Effect.gen(function* () {
        const snapshots = yield* getUserWageSnapshots(userId, skipAuthCheck);
        const snapshotMap = new Map<string, WageSnapshot>();

        // Find baseline snapshot once for fallback
        const baselineSnapshot = snapshots.find((s) => s.from_date === null);

        // Filter to only dated snapshots and sort ascending by from_date for binary search
        // (DB returns DESC, so we reverse for ascending order)
        const datedSnapshots = snapshots
          .filter((s): s is WageSnapshot & { from_date: string } => s.from_date !== null)
          .reverse(); // Now sorted ascending by from_date

        // Binary search: find the latest snapshot where from_date <= targetDate
        const findSnapshotForDate = (targetDate: string): WageSnapshot | null => {
          if (datedSnapshots.length === 0) return null;

          let left = 0;
          let right = datedSnapshots.length - 1;
          let result: WageSnapshot | null = null;

          while (left <= right) {
            const mid = Math.floor((left + right) / 2);
            const midDate = datedSnapshots[mid].from_date;

            if (midDate <= targetDate) {
              // This snapshot is valid, but there might be a later one that's still valid
              result = datedSnapshots[mid];
              left = mid + 1;
            } else {
              // This snapshot starts after our target date, look earlier
              right = mid - 1;
            }
          }

          return result;
        };

        for (const shiftDate of dates) {
          // Use binary search for O(log n) lookup
          const applicableSnapshot = findSnapshotForDate(shiftDate);

          // Use dated snapshot if found, otherwise fall back to baseline
          const snapshotToUse = applicableSnapshot || baselineSnapshot;

          if (snapshotToUse) {
            snapshotMap.set(shiftDate, snapshotToUse);
          }
        }

        return snapshotMap as ReadonlyMap<string, WageSnapshot>;
      });

    /**
     * Get snapshot for a single date
     * @param skipAuthCheck - Skip authentication when true (for shared access via RLS)
     */
    const getSnapshotForDate = (userId: string, date: string, skipAuthCheck = false) =>
      Effect.gen(function* () {
        const snapshots = yield* getUserWageSnapshots(userId, skipAuthCheck);

        // Find baseline snapshot for fallback
        const baselineSnapshot = snapshots.find((s) => s.from_date === null);

        // Find the first dated snapshot where from_date <= date
        const applicableSnapshot = snapshots.find(
          (s) => s.from_date !== null && s.from_date <= date
        );

        // Use dated snapshot if found, otherwise fall back to baseline
        return applicableSnapshot || baselineSnapshot || null;
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
          skipAuthCheck = false,
          year,
          month,
        } = options;

        // Verify authentication (unless explicitly skipped for shared access)
        if (!skipAuthCheck) {
          yield* auth.verifyUserId(userId);
        }

        // Fetch user settings
        // When skipAuthCheck is true (shared access), query directly to bypass SettingsService auth
        let userSettings: UserSettings = {};
        if (skipAuthCheck) {
          // Direct query for shared access (RLS handles authorization)
          const settingsResult = yield* supabase.query(
            async (client) =>
              await client
                .from("user_settings")
                .select("*")
                .eq("user_id", userId)
                .maybeSingle(),
            { retries: 2 }
          );
          userSettings = (settingsResult as any) ?? {};
        } else {
          const userSettingsResult = yield* settings.getUserSettings(userId);
          userSettings = (userSettingsResult as any) ?? {};
        }

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

        // Fetch recurring shifts
        const recurringQuery = async (client: any) =>
          await client
            .from("recurring_shifts")
            .select("*")
            .eq("user_id", userId);

        // Execute queries in parallel
        const [shifts, recurringShifts] = yield* Effect.all(
          [
            supabase.query(shiftsQuery, { retries: 2 }),
            supabase.query(recurringQuery, { retries: 2 }),
          ],
          { concurrency: 2 }
        );

        // Collect all shift dates for batch snapshot lookup
        const shiftDates = (shifts ?? []).map((s: ShiftRow) => s.shift_date);

        // Generate recurring virtual shifts ONCE and cache the results
        // Previously this was done twice: once for dates, once for computation
        const startYear = new Date(startDate).getFullYear();
        const startMonth = new Date(startDate).getMonth() + 1;
        const endYear = new Date(endDate).getFullYear();
        const endMonth = new Date(endDate).getMonth() + 1;

        // Structure: Map<recurringId, virtualShifts[]>
        const virtualShiftsByRecurring = new Map<string, Array<{ date: string; weekday: number }>>();
        const virtualShiftDates: string[] = [];

        for (const recurring of (recurringShifts ?? []) as DbRecurringShift[]) {
          const recurringVirtuals: Array<{ date: string; weekday: number }> = [];
          let currentYear = startYear;
          let currentMonth = startMonth;

          while (
            currentYear < endYear ||
            (currentYear === endYear && currentMonth <= endMonth)
          ) {
            const virtualShifts = generateVirtualShiftsForMonth(
              { year: currentYear, month: currentMonth },
              {
                start_time: cleanTime(recurring.start_time),
                end_time: cleanTime(recurring.end_time),
                repeat_interval_weeks: recurring.repeat_interval_weeks as
                  | 0
                  | 1
                  | 2
                  | 3
                  | 4
                  | 5
                  | 6
                  | 7
                  | 8,
                selected_days: recurring.selected_days,
                end_condition: recurring.end_condition,
                exclusions: recurring.exclusions || [],
              }
            );

            // Filter to date range and collect
            for (const vs of virtualShifts) {
              if (vs.date >= startDate && vs.date <= endDate) {
                recurringVirtuals.push(vs);
                virtualShiftDates.push(vs.date);
              }
            }

            // Move to next month
            currentMonth++;
            if (currentMonth > 12) {
              currentMonth = 1;
              currentYear++;
            }
          }

          virtualShiftsByRecurring.set(recurring.id, recurringVirtuals);
        }

        // Fetch snapshots for all dates (shifts + virtual shifts) in one batch
        const allDates = [...shiftDates, ...virtualShiftDates];
        const snapshotMap = yield* getSnapshotsForDates(userId, allDates, skipAuthCheck);

        // Compute regular shifts
        const computedShifts = ((shifts ?? []) as ShiftRow[]).map((shift) => {
          const snapshot = snapshotMap.get(shift.shift_date) ?? null;
          // Attach supplement_rules_snapshot from wage snapshot for UI components
          // This allows CustomSupplementsModal to show correct supplement rules
          // Priority: existing shift snapshot > wage snapshot > null
          const supplementRulesSnapshot = shift.supplement_rules_snapshot
            ?? (snapshot?.supplements ? snapshot.supplements : null);
          return {
            ...shift,
            supplement_rules_snapshot: supplementRulesSnapshot,
            computed: computeShift(shift, userSettings, PRESET_SUPPLEMENT_RULES, snapshot),
            // Include tax settings from snapshot for after-tax calculations
            tax_enabled: snapshot?.tax_enabled ?? false,
            tax_percentage: snapshot?.tax_percentage ?? 0,
          };
        });

        // Compute recurring virtual shifts using cached generation results
        const recurringVirtualShifts: ShiftWithComputations[] = [];
        for (const recurring of (recurringShifts ?? []) as DbRecurringShift[]) {
          const cachedVirtuals = virtualShiftsByRecurring.get(recurring.id) ?? [];

          for (const virtualShift of cachedVirtuals) {
            const snapshot = snapshotMap.get(virtualShift.date) ?? null;

            // Check if recurring shift has date-specific custom supplements for this virtual shift date
            const customSupplements = recurring.date_specific_supplements?.[virtualShift.date] ?? null;

            const computed = computeShift(
              {
                id: `virtual-${recurring.id}-${virtualShift.date}`,
                user_id: userId,
                shift_date: virtualShift.date,
                start_time: cleanTime(recurring.start_time),
                end_time: cleanTime(recurring.end_time),
                custom_supplements: customSupplements as any,
                recurring_id: recurring.id,
                recurring_anchor_weekday: virtualShift.weekday,
              },
              userSettings,
              PRESET_SUPPLEMENT_RULES,
              snapshot
            );

            // Attach supplement_rules_snapshot from wage snapshot for UI components
            const supplementRulesSnapshot = snapshot?.supplements ? snapshot.supplements : null;

            recurringVirtualShifts.push({
              id: `virtual-${recurring.id}-${virtualShift.date}`,
              user_id: userId,
              shift_date: virtualShift.date,
              start_time: cleanTime(recurring.start_time),
              end_time: cleanTime(recurring.end_time),
              custom_supplements: customSupplements as any,
              supplement_rules_snapshot: supplementRulesSnapshot,
              recurring_id: recurring.id,
              recurring_anchor_weekday: virtualShift.weekday,
              computed,
              // Include tax settings from snapshot for after-tax calculations
              tax_enabled: snapshot?.tax_enabled ?? false,
              tax_percentage: snapshot?.tax_percentage ?? 0,
            });
          }
        }

        // Merge shifts and recurring virtual shifts, then sort by date ascending
        // (Virtual shifts were appended unsorted, so we need to sort the merged array)
        const allShifts = [...computedShifts, ...recurringVirtualShifts].sort(
          (a, b) => a.shift_date.localeCompare(b.shift_date)
        );

        // Compute aggregates
        const aggregates: ShiftsAggregates = allShifts.reduce(
          (acc, shift) => ({
            totalHours: acc.totalHours + shift.computed.paidHours,
            totalEarnings: acc.totalEarnings + shift.computed.gross,
          }),
          { totalHours: 0, totalEarnings: 0 }
        );

        // Fetch payout month tax settings if year and month are provided
        let payoutTaxSettings: PayoutTaxSettings = null;

        if (year && month) {
          // Get payroll day from user settings (default to 1 if not set)
          const payrollDay = (userSettings as DbUserSettings)?.payroll_day ?? 1;
          const payoutDate = calculatePayoutDate(year, month, payrollDay);

          const payoutSnapshot = yield* getSnapshotForDate(userId, payoutDate, skipAuthCheck);

          if (payoutSnapshot) {
            payoutTaxSettings = {
              enabled: payoutSnapshot.tax_enabled ?? false,
              percentage: payoutSnapshot.tax_percentage ?? 0,
            };
          }
        }

        return {
          shifts: allShifts as readonly ShiftWithComputations[],
          defaultView: (userSettings as DbUserSettings)?.default_shifts_view || "calendar",
          settings: userSettings,
          aggregates,
          payoutTaxSettings,
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
