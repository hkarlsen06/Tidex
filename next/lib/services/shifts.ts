/**
 * Shifts Service Layer
 *
 * Effect-based service for shift data access with:
 * - Parallel query execution for shifts and recurring shifts
 * - Automatic snapshot resolution
 * - Type-safe error handling
 * - Caching for performance
 */

import "server-only";
import { Context, Effect, Layer } from "effect";
import type { SupabaseClient } from "@supabase/supabase-js";
import { AuthService } from "./auth";
import { SupabaseService } from "./supabase";
import { SettingsService, type DbUserSettings } from "./settings";
import { DatabaseError, AuthError, NotFoundError, TimeoutError, SupabaseError } from "../errors/tagged";
import {
  computeShift,
  type ShiftRow,
  type ShiftWithComputations,
  type UserSettings,
  type CustomSupplementsData,
  PRESET_SUPPLEMENT_RULES,
  type WageSnapshot,
  type Job,
} from "../payroll";
import { getCurrentYearMonth, getMonthStart, getMonthEnd } from "../date-utils";
import { generateVirtualShiftsForMonth } from "../recurring/utils";
import type { RecurringShiftRow } from "../recurring/types";
import { cleanTime } from "../time-utils";

export type ShiftLoadOptions = {
  readonly userId: string;
  readonly startDate?: string;
  readonly endDate?: string;
  readonly limit?: number;
  readonly jobId?: string;
  readonly skipAuthCheck?: boolean;
  readonly year?: number;
  readonly month?: number;
};

export type PayoutTaxSettings = {
  readonly enabled: boolean;
  readonly percentage: number;
} | null;

export type ShiftsAggregates = {
  readonly totalHours: number;
  readonly totalEarnings: number;
};

export type ShiftData = {
  readonly shifts: readonly ShiftWithComputations[];
  readonly defaultView: string;
  readonly settings: UserSettings;
  readonly jobs: readonly Job[];
  readonly aggregates: ShiftsAggregates;
  readonly payoutTaxSettings: PayoutTaxSettings;
  readonly currentPayoutTaxSettings: PayoutTaxSettings;
  readonly breakDeductionEnabled: boolean;
};

type DbRecurringShift = RecurringShiftRow & {
  user_id: string;
  job_id?: string | null;
};

type SnapshotBucket = {
  readonly dated: readonly (WageSnapshot & { from_date: string })[];
  readonly baseline: WageSnapshot | null;
};

const LEGACY_SNAPSHOT_KEY = "__legacy__";

const snapshotKeyForJob = (jobId?: string | null): string => jobId ?? LEGACY_SNAPSHOT_KEY;

const buildSnapshotBuckets = (
  snapshots: readonly WageSnapshot[]
): ReadonlyMap<string, SnapshotBucket> => {
  const mutable = new Map<string, { dated: (WageSnapshot & { from_date: string })[]; baseline: WageSnapshot | null }>();

  for (const snapshot of snapshots) {
    const key = snapshotKeyForJob(snapshot.job_id ?? null);
    const bucket = mutable.get(key) ?? { dated: [], baseline: null };

    if (snapshot.from_date === null) {
      bucket.baseline = snapshot;
    } else {
      bucket.dated.push(snapshot as WageSnapshot & { from_date: string });
    }

    mutable.set(key, bucket);
  }

  for (const bucket of mutable.values()) {
    bucket.dated.sort((a, b) => b.from_date.localeCompare(a.from_date));
  }

  return mutable;
};

const resolveSnapshotForDate = (
  buckets: ReadonlyMap<string, SnapshotBucket>,
  snapshots: readonly WageSnapshot[],
  date: string,
  jobId?: string | null
): WageSnapshot | null => {
  const preferredKeys = [snapshotKeyForJob(jobId), LEGACY_SNAPSHOT_KEY];

  for (const key of preferredKeys) {
    const bucket = buckets.get(key);
    if (!bucket) continue;

    const dated = bucket.dated.find((s) => s.from_date <= date);
    if (dated) return dated;
  }

  for (const key of preferredKeys) {
    const baseline = buckets.get(key)?.baseline ?? null;
    if (baseline) return baseline;
  }

  return snapshots.find((s) => s.from_date === null) ?? null;
};

const resolveBaselineSnapshot = (
  buckets: ReadonlyMap<string, SnapshotBucket>,
  snapshots: readonly WageSnapshot[],
  jobId?: string | null
): WageSnapshot | null => {
  const preferredKeys = [snapshotKeyForJob(jobId), LEGACY_SNAPSHOT_KEY];

  for (const key of preferredKeys) {
    const baseline = buckets.get(key)?.baseline ?? null;
    if (baseline) return baseline;
  }

  return snapshots.find((s) => s.from_date === null) ?? null;
};

export class ShiftsService extends Context.Tag("ShiftsService")<
  ShiftsService,
  {
    readonly getShiftsWithComputations: (
      options: ShiftLoadOptions
    ) => Effect.Effect<
      ShiftData,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

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

export const ShiftsServiceLive = Layer.effect(
  ShiftsService,
  Effect.gen(function* () {
    const auth = yield* AuthService;
    const supabase = yield* SupabaseService;
    const settings = yield* SettingsService;

    const getDefaultStartDate = (): string => {
      const { year, month } = getCurrentYearMonth();
      return getMonthStart(year, month);
    };

    const getDefaultEndDate = (): string => {
      const { year, month } = getCurrentYearMonth();
      return getMonthEnd(year, month);
    };

    const calculatePayoutDate = (
      earningsYear: number,
      earningsMonth: number,
      payrollDay: number
    ): string => {
      let payoutYear = earningsYear;
      let payoutMonth = earningsMonth + 1;

      if (payoutMonth > 12) {
        payoutMonth = 1;
        payoutYear += 1;
      }

      const daysInPayoutMonth = new Date(payoutYear, payoutMonth, 0).getDate();
      const effectivePayrollDay = Math.min(payrollDay, daysInPayoutMonth);

      return `${payoutYear}-${String(payoutMonth).padStart(2, "0")}-${String(effectivePayrollDay).padStart(2, "0")}`;
    };

    const getUserWageSnapshots = (
      userId: string,
      skipAuthCheck = false,
      jobId?: string
    ) =>
      Effect.gen(function* () {
        if (!skipAuthCheck) {
          yield* auth.verifyUserId(userId);
        }

        const snapshots = yield* supabase.query(
          async (client) => {
            let query = client
              .from("wage_snapshots")
              .select("*")
              .eq("user_id", userId)
              .is("deleted_at", null)
              .order("from_date", { ascending: false, nullsFirst: false });

            if (jobId) {
              query = query.eq("job_id", jobId);
            }

            return await query;
          },
          { retries: 2 }
        );

        return (snapshots ?? []) as WageSnapshot[];
      });

    const getSnapshotsForDates = (userId: string, dates: readonly string[], skipAuthCheck = false, jobId?: string) =>
      Effect.gen(function* () {
        const snapshots = yield* getUserWageSnapshots(userId, skipAuthCheck, jobId);
        const buckets = buildSnapshotBuckets(snapshots);
        const snapshotMap = new Map<string, WageSnapshot>();

        for (const date of dates) {
          const snapshot = resolveSnapshotForDate(buckets, snapshots, date, jobId ?? null);
          if (snapshot) {
            snapshotMap.set(date, snapshot);
          }
        }

        return snapshotMap as ReadonlyMap<string, WageSnapshot>;
      });

    const getShiftsWithComputations = (options: ShiftLoadOptions) =>
      Effect.gen(function* () {
        const {
          userId,
          startDate = getDefaultStartDate(),
          endDate = getDefaultEndDate(),
          limit = 50,
          jobId,
          skipAuthCheck = false,
          year,
          month,
        } = options;

        if (!skipAuthCheck) {
          yield* auth.verifyUserId(userId);
        }

        let userSettings: DbUserSettings | null = null;
        if (skipAuthCheck) {
          const settingsResult = yield* supabase.query(
            async (client) =>
              await client
                .from("user_settings")
                .select("*")
                .eq("user_id", userId)
                .maybeSingle(),
            { retries: 2 }
          ).pipe(
            Effect.catchTag("DatabaseError", (error) => {
              if (error.code === "NO_DATA") {
                return Effect.succeed(null);
              }
              return Effect.fail(error);
            })
          );
          userSettings = settingsResult as DbUserSettings | null;
        } else {
          userSettings = yield* settings.getUserSettings(userId);
        }

        const shiftsQuery = async (client: SupabaseClient) => {
          let query = client
            .from("user_shifts")
            .select("*")
            .eq("user_id", userId)
            .is("deleted_at", null)
            .order("shift_date", { ascending: false });

          if (jobId) {
            query = query.eq("job_id", jobId);
          }

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

        const recurringQuery = async (client: SupabaseClient) => {
          let query = client
            .from("recurring_shifts")
            .select("*")
            .eq("user_id", userId)
            .is("deleted_at", null);

          if (jobId) {
            query = query.eq("job_id", jobId);
          }

          return await query;
        };

        const jobsQuery = async (client: SupabaseClient) =>
          await client
            .from("jobs")
            .select("*")
            .eq("user_id", userId)
            .is("deleted_at", null)
            .order("sort_order", { ascending: true })
            .order("created_at", { ascending: true });

        const [shifts, recurringShifts, jobs, allSnapshots] = yield* Effect.all(
          [
            supabase.query(shiftsQuery, { retries: 2 }),
            supabase.query(recurringQuery, { retries: 2 }),
            supabase.query(jobsQuery, { retries: 2 }),
            getUserWageSnapshots(userId, skipAuthCheck),
          ],
          { concurrency: 4 }
        );

        const normalizedJobs = ((jobs ?? []) as Job[]).filter((j) => j.deleted_at == null);
        const jobsById = new Map(normalizedJobs.map((j) => [j.id, j] as const));
        const defaultJob =
          normalizedJobs.find((j) => j.is_default && j.archived_at == null) ??
          normalizedJobs.find((j) => j.is_default) ??
          normalizedJobs[0] ??
          null;
        const defaultJobId = defaultJob?.id ?? null;

        const snapshots = (allSnapshots ?? []) as WageSnapshot[];
        const snapshotBuckets = buildSnapshotBuckets(snapshots);

        const fallbackPayrollDay = userSettings?.payroll_day ?? 1;
        const payrollDayForJob = (targetJobId?: string | null): number =>
          jobsById.get(targetJobId ?? "")?.payroll_day ?? defaultJob?.payroll_day ?? fallbackPayrollDay;

        const payoutDateFor = (date: string, targetJobId?: string | null): string => {
          const [yearPart, monthPart] = date.split("-").map(Number);
          return calculatePayoutDate(yearPart, monthPart, payrollDayForJob(targetJobId));
        };

        const startYear = new Date(startDate).getFullYear();
        const startMonth = new Date(startDate).getMonth() + 1;
        const endYear = new Date(endDate).getFullYear();
        const endMonth = new Date(endDate).getMonth() + 1;

        const virtualShiftsByRecurring = new Map<string, Array<{ date: string; weekday: number }>>();

        for (const recurring of (recurringShifts ?? []) as DbRecurringShift[]) {
          const recurringVirtuals: Array<{ date: string; weekday: number }> = [];
          let currentYear = startYear;
          let currentMonth = startMonth;

          while (currentYear < endYear || (currentYear === endYear && currentMonth <= endMonth)) {
            const virtualShifts = generateVirtualShiftsForMonth(
              { year: currentYear, month: currentMonth },
              {
                start_time: cleanTime(recurring.start_time),
                end_time: cleanTime(recurring.end_time),
                repeat_interval_weeks: recurring.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8,
                selected_days: recurring.selected_days,
                end_condition: recurring.end_condition,
                exclusions: recurring.exclusions || [],
              }
            );

            for (const vs of virtualShifts) {
              if (vs.date >= startDate && vs.date <= endDate) {
                recurringVirtuals.push(vs);
              }
            }

            currentMonth += 1;
            if (currentMonth > 12) {
              currentMonth = 1;
              currentYear += 1;
            }
          }

          virtualShiftsByRecurring.set(recurring.id, recurringVirtuals);
        }

        const computedShifts = ((shifts ?? []) as ShiftRow[]).map((shift) => {
          const shiftJobId = shift.job_id ?? defaultJobId;
          const snapshot = resolveSnapshotForDate(snapshotBuckets, snapshots, shift.shift_date, shiftJobId);
          const payoutDate = payoutDateFor(shift.shift_date, shiftJobId);
          const taxSnapshot = resolveSnapshotForDate(snapshotBuckets, snapshots, payoutDate, shiftJobId);

          const supplementRulesSnapshot = shift.supplement_rules_snapshot
            ?? (snapshot?.supplements ? snapshot.supplements : null);

          return {
            ...shift,
            job_id: shiftJobId,
            supplement_rules_snapshot: supplementRulesSnapshot,
            computed: computeShift(
              shift,
              userSettings ?? {},
              PRESET_SUPPLEMENT_RULES,
              snapshot,
              shiftJobId ? jobsById.get(shiftJobId) ?? null : null
            ),
            tax_enabled: taxSnapshot?.tax_enabled ?? false,
            tax_percentage: taxSnapshot?.tax_percentage ?? 0,
          };
        });

        const recurringVirtualShifts: ShiftWithComputations[] = [];
        for (const recurring of (recurringShifts ?? []) as DbRecurringShift[]) {
          const recurringJobId = recurring.job_id ?? defaultJobId;
          const cachedVirtuals = virtualShiftsByRecurring.get(recurring.id) ?? [];

          for (const virtualShift of cachedVirtuals) {
            const snapshot = resolveSnapshotForDate(snapshotBuckets, snapshots, virtualShift.date, recurringJobId);
            const payoutDate = payoutDateFor(virtualShift.date, recurringJobId);
            const taxSnapshot = resolveSnapshotForDate(snapshotBuckets, snapshots, payoutDate, recurringJobId);

            const customSupplements: CustomSupplementsData | null =
              recurring.date_specific_supplements?.[virtualShift.date] ?? null;

            const syntheticShift: ShiftRow = {
              id: `virtual-${recurring.id}-${virtualShift.date}`,
              user_id: userId,
              job_id: recurringJobId,
              shift_date: virtualShift.date,
              start_time: cleanTime(recurring.start_time),
              end_time: cleanTime(recurring.end_time),
              custom_supplements: customSupplements,
              recurring_id: recurring.id,
              recurring_anchor_weekday: virtualShift.weekday,
            };

            const computed = computeShift(
              syntheticShift,
              userSettings ?? {},
              PRESET_SUPPLEMENT_RULES,
              snapshot,
              recurringJobId ? jobsById.get(recurringJobId) ?? null : null
            );

            recurringVirtualShifts.push({
              ...syntheticShift,
              supplement_rules_snapshot: snapshot?.supplements ? snapshot.supplements : null,
              computed,
              tax_enabled: taxSnapshot?.tax_enabled ?? false,
              tax_percentage: taxSnapshot?.tax_percentage ?? 0,
            });
          }
        }

        const allShifts = [...computedShifts, ...recurringVirtualShifts].sort((a, b) =>
          a.shift_date.localeCompare(b.shift_date)
        );

        const aggregates: ShiftsAggregates = allShifts.reduce(
          (acc, shift) => ({
            totalHours: acc.totalHours + shift.computed.paidHours,
            totalEarnings: acc.totalEarnings + shift.computed.gross,
          }),
          { totalHours: 0, totalEarnings: 0 }
        );

        let payoutTaxSettings: PayoutTaxSettings = null;
        let currentPayoutTaxSettings: PayoutTaxSettings = null;

        const summaryJobId = jobId ?? defaultJobId;

        if (year && month) {
          const payoutDate = calculatePayoutDate(year, month, payrollDayForJob(summaryJobId));
          const payoutSnapshot = resolveSnapshotForDate(snapshotBuckets, snapshots, payoutDate, summaryJobId);

          if (payoutSnapshot) {
            payoutTaxSettings = {
              enabled: payoutSnapshot.tax_enabled ?? false,
              percentage: payoutSnapshot.tax_percentage ?? 0,
            };
          }

          const prevMonth = month === 1 ? 12 : month - 1;
          const prevYear = month === 1 ? year - 1 : year;
          const currentPayoutDate = calculatePayoutDate(prevYear, prevMonth, payrollDayForJob(summaryJobId));
          const currentPayoutSnapshot = resolveSnapshotForDate(
            snapshotBuckets,
            snapshots,
            currentPayoutDate,
            summaryJobId
          );

          if (currentPayoutSnapshot) {
            currentPayoutTaxSettings = {
              enabled: currentPayoutSnapshot.tax_enabled ?? false,
              percentage: currentPayoutSnapshot.tax_percentage ?? 0,
            };
          }
        }

        const baselineSnapshot = resolveBaselineSnapshot(snapshotBuckets, snapshots, summaryJobId);
        const breakDeductionEnabled = baselineSnapshot?.break_enabled ?? true;

        return {
          shifts: allShifts as readonly ShiftWithComputations[],
          defaultView: userSettings?.default_shifts_view ?? "calendar",
          settings: userSettings ?? {},
          jobs: normalizedJobs,
          aggregates,
          payoutTaxSettings,
          currentPayoutTaxSettings,
          breakDeductionEnabled,
        };
      });

    return {
      getShiftsWithComputations,
      getSnapshotsForDates,
    };
  })
);

export const withShifts = <A, E, R>(
  effect: Effect.Effect<A, E, R | ShiftsService>
): Effect.Effect<
  A,
  E,
  Exclude<R, ShiftsService> | AuthService | SupabaseService | SettingsService
> => Effect.provide(effect, ShiftsServiceLive);
