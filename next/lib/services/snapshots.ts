/**
 * Snapshots Service Layer
 *
 * Effect-based service for wage snapshot management with:
 * - CRUD operations for wage snapshots
 * - Snapshot lookup by date
 * - Validation and conflict detection
 * - Type-safe error handling
 *
 * Usage:
 * ```typescript
 * const program = Effect.gen(function* () {
 *   const snapshots = yield* SnapshotsService
 *   const snapshot = yield* snapshots.getSnapshotForDate(userId, "2025-01-15")
 *   return snapshot
 * }).pipe(
 *   Effect.provide(SnapshotsServiceLive)
 * )
 * ```
 */

import "server-only";
import { Context, Effect, Layer, Cache, Duration } from "effect";
import type { SupabaseClient } from "@supabase/supabase-js";
import { AuthService } from "./auth";
import { SupabaseService } from "./supabase";
import {
  DatabaseError,
  AuthError,
  NotFoundError,
  TimeoutError,
  SupabaseError,
  ValidationError,
} from "../errors/tagged";
import type { WageSnapshot, SupplementRule, BreakMethod } from "../payroll/types";

/**
 * Wage snapshot creation/update data
 * Includes wage, supplement, tax, and break deduction settings
 */
export type SnapshotData = {
  readonly from_date: string | null;
  readonly hourly_wage: number;
  readonly wage_level: number | null;
  readonly supplements: { rules: SupplementRule[] };
  // Tax settings
  readonly tax_enabled: boolean;
  readonly tax_percentage: number;
  // Break deduction settings
  readonly break_enabled: boolean;
  readonly break_method: BreakMethod;
  readonly break_threshold_hours: number;
  readonly break_deduction_minutes: number;
};

/**
 * @deprecated Use SnapshotData instead
 */
export type CreateSnapshotData = SnapshotData;

/**
 * @deprecated Use SnapshotData instead
 */
export type UpdateSnapshotData = SnapshotData;

/**
 * Snapshots Service Interface
 */
export class SnapshotsService extends Context.Tag("SnapshotsService")<
  SnapshotsService,
  {
    /**
     * Get all wage snapshots for authenticated user
     * Returns snapshots ordered by from_date DESC (newest first)
     */
    readonly getUserWageSnapshots: (
      userId: string
    ) => Effect.Effect<
      readonly WageSnapshot[],
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get the applicable wage snapshot for a specific shift date
     * Finds the most recent snapshot where from_date <= shiftDate
     * Falls back to baseline snapshot (from_date = NULL) if no dated snapshot matches
     */
    readonly getSnapshotForDate: (
      userId: string,
      shiftDate: string
    ) => Effect.Effect<
      WageSnapshot | null,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get applicable snapshots for multiple shift dates (batch lookup)
     * Returns a Map of shiftDate -> WageSnapshot
     */
    readonly getSnapshotsForDates: (
      userId: string,
      shiftDates: readonly string[]
    ) => Effect.Effect<
      ReadonlyMap<string, WageSnapshot>,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Check if a wage snapshot with the given from_date already exists
     * Used for validation before creating/updating snapshots
     */
    readonly checkExistingSnapshot: (
      userId: string,
      fromDate: string | null,
      excludeId?: string
    ) => Effect.Effect<
      boolean,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Create a new wage snapshot
     */
    readonly createWageSnapshot: (
      userId: string,
      data: CreateSnapshotData
    ) => Effect.Effect<
      { id: string },
      DatabaseError | AuthError | NotFoundError | ValidationError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Update an existing wage snapshot
     */
    readonly updateWageSnapshot: (
      userId: string,
      id: string,
      data: UpdateSnapshotData
    ) => Effect.Effect<
      void,
      DatabaseError | AuthError | NotFoundError | ValidationError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Count shifts affected by a wage snapshot
     * Returns the count of shifts between this snapshot and the next one
     */
    readonly countAffectedShifts: (
      userId: string,
      snapshotId: string
    ) => Effect.Effect<
      number,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Delete a wage snapshot
     * Cannot delete baseline snapshot if other dated snapshots exist
     */
    readonly deleteWageSnapshot: (
      userId: string,
      id: string
    ) => Effect.Effect<
      { affectedShiftCount: number },
      | DatabaseError
      | AuthError
      | NotFoundError
      | ValidationError
      | TimeoutError
      | SupabaseError,
      never
    >;
  }
>() {}

/**
 * Live implementation of SnapshotsService
 *
 * Uses Effect Cache for snapshot lookups with 10-minute TTL
 */
export const SnapshotsServiceLive = Layer.effect(
  SnapshotsService,
  Effect.gen(function* () {
    const auth = yield* AuthService;
    const supabase = yield* SupabaseService;

    // Create cache for user wage snapshots (10 minute TTL)
    const snapshotsCache = yield* Cache.make({
      capacity: 100,
      timeToLive: Duration.minutes(10),
      lookup: (userId: string) =>
        Effect.gen(function* () {
          yield* auth.verifyUserId(userId);

          const snapshots = yield* supabase.query(
            async (client) =>
              await client
                .from("wage_snapshots")
                .select("*")
                .eq("user_id", userId)
                .is("deleted_at", null) // Exclude soft-deleted snapshots
                .order("from_date", { ascending: false, nullsFirst: false }),
            { retries: 2 }
          );

          return (snapshots ?? []) as readonly WageSnapshot[];
        }),
    });

    /**
     * Get all wage snapshots for user
     */
    const getUserWageSnapshots = (userId: string) => snapshotsCache.get(userId);

    /**
     * Get snapshot for a specific date
     */
    const getSnapshotForDate = (userId: string, shiftDate: string) =>
      Effect.gen(function* () {
        const snapshots = yield* getUserWageSnapshots(userId);

        // Find the first dated snapshot where from_date <= shiftDate
        const applicableSnapshot = snapshots.find(
          (snapshot) => snapshot.from_date !== null && snapshot.from_date <= shiftDate
        );

        if (applicableSnapshot) {
          return applicableSnapshot;
        }

        // If no dated snapshot matches, use the baseline snapshot (from_date = NULL)
        const baselineSnapshot = snapshots.find((snapshot) => snapshot.from_date === null);

        return baselineSnapshot ?? null;
      });

    /**
     * Get snapshots for multiple dates (batch lookup)
     */
    const getSnapshotsForDates = (userId: string, shiftDates: readonly string[]) =>
      Effect.gen(function* () {
        const snapshots = yield* getUserWageSnapshots(userId);
        const snapshotMap = new Map<string, WageSnapshot>();

        // Find baseline snapshot once for fallback
        const baselineSnapshot = snapshots.find((s) => s.from_date === null);

        for (const shiftDate of shiftDates) {
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
     * Check if a snapshot exists for a given date
     */
    const checkExistingSnapshot = (
      userId: string,
      fromDate: string | null,
      excludeId?: string
    ) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        const queryEffect = async (client: SupabaseClient) => {
          let query = client
            .from("wage_snapshots")
            .select("id")
            .eq("user_id", userId)
            .is("deleted_at", null); // Exclude soft-deleted snapshots

          // Handle NULL from_date (baseline snapshot)
          if (fromDate === null) {
            query = query.is("from_date", null);
          } else {
            query = query.eq("from_date", fromDate);
          }

          // Exclude specific snapshot (for update validation)
          if (excludeId) {
            query = query.neq("id", excludeId);
          }

          return await query.single();
        };

        const result = yield* supabase
          .query(queryEffect, { retries: 2 })
          .pipe(
            Effect.map(() => true),
            Effect.catchTag("DatabaseError", (error) => {
              // NO_DATA error means snapshot doesn't exist (what we want)
              if (error.code === "NO_DATA") {
                return Effect.succeed(false);
              }
              // Other errors are real failures
              return Effect.fail(error);
            })
          );

        return result;
      });

    /**
     * Create a new wage snapshot
     */
    const createWageSnapshot = (userId: string, data: CreateSnapshotData) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        const snapshot = yield* supabase.query(
          async (client) =>
            await client
              .from("wage_snapshots")
              .insert({
                user_id: userId,
                from_date: data.from_date,
                hourly_wage: data.hourly_wage,
                wage_level: data.wage_level,
                supplements: data.supplements,
                tax_enabled: data.tax_enabled,
                tax_percentage: data.tax_percentage,
                break_enabled: data.break_enabled,
                break_method: data.break_method,
                break_threshold_hours: data.break_threshold_hours,
                break_deduction_minutes: data.break_deduction_minutes,
              })
              .select("id")
              .single(),
          { retries: 1 }
        );

        return { id: (snapshot as unknown as { id: string }).id };
      });

    /**
     * Update an existing wage snapshot
     */
    const updateWageSnapshot = (userId: string, id: string, data: UpdateSnapshotData) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        yield* supabase.query(
          async (client) =>
            await client
              .from("wage_snapshots")
              .update({
                from_date: data.from_date,
                hourly_wage: data.hourly_wage,
                wage_level: data.wage_level,
                supplements: data.supplements,
                tax_enabled: data.tax_enabled,
                tax_percentage: data.tax_percentage,
                break_enabled: data.break_enabled,
                break_method: data.break_method,
                break_threshold_hours: data.break_threshold_hours,
                break_deduction_minutes: data.break_deduction_minutes,
              })
              .eq("id", id)
              .eq("user_id", userId)
              .is("deleted_at", null), // Only update non-deleted snapshots
          { retries: 1 }
        );

        return Effect.void;
      });

    /**
     * Count shifts affected by a snapshot
     */
    const countAffectedShifts = (userId: string, snapshotId: string) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        // Get the snapshot's from_date
        const snapshot = yield* supabase.query(
          async (client) =>
            await client
              .from("wage_snapshots")
              .select("from_date")
              .eq("id", snapshotId)
              .eq("user_id", userId)
              .is("deleted_at", null) // Only find non-deleted snapshots
              .single(),
          { retries: 2 }
        );

        if (!snapshot) {
          return yield* Effect.fail(
            new NotFoundError({ resource: "Wage snapshot", id: snapshotId })
          );
        }

        // Get all snapshots to find the next one
        const snapshots = yield* getUserWageSnapshots(userId);
        const currentIndex = snapshots.findIndex((s) => s.id === snapshotId);

        if (currentIndex === -1) {
          return 0;
        }

        // Find the next snapshot (earlier date since snapshots are ordered DESC)
        const nextSnapshot = snapshots[currentIndex + 1] ?? null;

        // Count shifts between this snapshot and the next
        const snapshotFromDate = (snapshot as { from_date: string | null }).from_date;
        const countQuery = async (client: SupabaseClient) => {
          let query = client
            .from("user_shifts")
            .select("id", { count: "exact", head: true })
            .eq("user_id", userId)
            .is("deleted_at", null) // Only count non-deleted shifts
            .gte("shift_date", snapshotFromDate);

          if (nextSnapshot) {
            query = query.lt("shift_date", nextSnapshot.from_date);
          }

          return await query;
        };

        const countResult = yield* supabase.query(countQuery, { retries: 2 });

        // Extract count from result (Supabase returns { count: number } for head: true queries)
        // The result is typed as unknown from the generic query, so we need to extract the count
        if (typeof countResult === "object" && countResult !== null && "count" in countResult) {
          return (countResult as { count: number }).count;
        }
        return 0;
      });

    /**
     * Delete a wage snapshot
     */
    const deleteWageSnapshot = (userId: string, id: string) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        // Get the snapshot to check if it's baseline
        const snapshot = yield* supabase.query(
          async (client) =>
            await client
              .from("wage_snapshots")
              .select("from_date")
              .eq("id", id)
              .eq("user_id", userId)
              .is("deleted_at", null) // Only find non-deleted snapshots
              .single(),
          { retries: 2 }
        );

        if (!snapshot) {
          return yield* Effect.fail(
            new NotFoundError({ resource: "Wage snapshot", id })
          );
        }

        // If this is the baseline snapshot, check if other snapshots exist
        if ((snapshot as { from_date: string | null }).from_date === null) {
          const snapshots = yield* getUserWageSnapshots(userId);
          const datedSnapshots = snapshots.filter((s) => s.from_date !== null);

          if (datedSnapshots.length > 0) {
            return yield* Effect.fail(
              new ValidationError({
                message:
                  "Kan ikke slette grunntariffen når det finnes andre lønnsendringer. Slett de andre først.",
              })
            );
          }
        }

        // Count affected shifts before deletion
        const affectedShiftCount = yield* countAffectedShifts(userId, id);

        // Soft delete the snapshot by setting deleted_at
        yield* supabase.query(
          async (client) =>
            await client
              .from("wage_snapshots")
              .update({ deleted_at: new Date().toISOString() })
              .eq("id", id)
              .eq("user_id", userId)
              .is("deleted_at", null), // Only delete if not already deleted
          { retries: 1 }
        );

        return { affectedShiftCount };
      });

    return {
      getUserWageSnapshots,
      getSnapshotForDate,
      getSnapshotsForDates,
      checkExistingSnapshot,
      createWageSnapshot,
      updateWageSnapshot,
      countAffectedShifts,
      deleteWageSnapshot,
    };
  })
);

/**
 * Convenience function to provide SnapshotsServiceLive with dependencies
 */
export const withSnapshots = <A, E, R>(
  effect: Effect.Effect<A, E, R | SnapshotsService>
): Effect.Effect<A, E, Exclude<R, SnapshotsService> | AuthService | SupabaseService> =>
  Effect.provide(effect, SnapshotsServiceLive);
