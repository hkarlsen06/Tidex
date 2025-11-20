/**
 * Effect-based Payroll Calculation System
 *
 * This module wraps the pure payroll calculation functions with Effect for:
 * - Input validation with @effect/schema
 * - Typed error handling
 * - Composable calculation pipelines
 * - Property-based testing support
 *
 * The core calculation logic remains pure (in calc.ts) - this adds a
 * type-safe Effect wrapper around it.
 */

import { Effect, Schema, ParseResult } from "effect";
import { ValidationError } from "../errors/tagged";
import { computeShift as computeShiftPure } from "./calc";
import type {
  ShiftRow,
  UserSettings,
  SupplementRule,
  WageSnapshot,
  ShiftComputed,
  HHMM,
} from "./types";

/**
 * Schema for HH:MM time format validation
 */
const HHMMSchema = Schema.String.pipe(
  Schema.pattern(/^([01]\d|2[0-3]):([0-5]\d)$/),
  Schema.brand("HHMM"),
  Schema.annotations({
    message: () => "Time must be in HH:MM format (00:00-23:59)",
  })
);

/**
 * Schema for ISO date format (YYYY-MM-DD)
 */
const ISODateSchema = Schema.String.pipe(
  Schema.pattern(/^\d{4}-\d{2}-\d{2}$/),
  Schema.brand("ISODate"),
  Schema.annotations({
    message: () => "Date must be in YYYY-MM-DD format",
  })
);

/**
 * Schema for Break Method
 */
const BreakMethodSchema = Schema.Literal(
  "proportional",
  "base_only",
  "end_of_shift",
  "none"
);

/**
 * Schema for Supplement Rule
 */
const SupplementRuleSchema = Schema.Struct({
  days: Schema.Array(
    Schema.Number.pipe(
      Schema.int(),
      Schema.between(1, 7),
      Schema.annotations({
        message: () => "Day must be between 1-7 (Monday-Sunday)",
      })
    )
  ),
  from: HHMMSchema,
  to: HHMMSchema,
  rate: Schema.optional(
    Schema.Number.pipe(
      Schema.greaterThanOrEqualTo(0),
      Schema.annotations({
        message: () => "Rate must be non-negative",
      })
    )
  ),
  percent: Schema.optional(
    Schema.Number.pipe(
      Schema.greaterThanOrEqualTo(0),
      Schema.annotations({
        message: () => "Percent must be non-negative",
      })
    )
  ),
});

/**
 * Schema for Shift Row
 */
const ShiftRowSchema = Schema.Struct({
  id: Schema.UUID,
  user_id: Schema.UUID,
  shift_date: ISODateSchema,
  start_time: HHMMSchema,
  end_time: HHMMSchema,
  hourly_wage_snapshot: Schema.optional(Schema.NullOr(Schema.Number.pipe(Schema.greaterThan(0)))),
  supplement_rules_snapshot: Schema.optional(
    Schema.NullOr(
      Schema.Struct({
        rules: Schema.Array(SupplementRuleSchema),
      })
    )
  ),
  series_id: Schema.optional(Schema.String),
  series_anchor_weekday: Schema.optional(Schema.Number.pipe(Schema.int(), Schema.between(0, 6))),
});

/**
 * Schema for User Settings
 */
const UserSettingsSchema = Schema.Struct({
  pause_deduction_enabled: Schema.optional(Schema.NullOr(Schema.Boolean)),
  pause_deduction_method: Schema.optional(Schema.NullOr(BreakMethodSchema)),
  pause_threshold_hours: Schema.optional(
    Schema.NullOr(Schema.Number.pipe(Schema.greaterThan(0)))
  ),
  pause_deduction_minutes: Schema.optional(
    Schema.NullOr(Schema.Number.pipe(Schema.greaterThanOrEqualTo(0)))
  ),
  tax_deduction_enabled: Schema.optional(Schema.NullOr(Schema.Boolean)),
  tax_percentage: Schema.optional(
    Schema.NullOr(Schema.Number.pipe(Schema.between(0, 100)))
  ),
  half_tax_month: Schema.optional(
    Schema.NullOr(Schema.Number.pipe(Schema.int(), Schema.between(1, 12)))
  ),
  payroll_day: Schema.optional(
    Schema.NullOr(Schema.Number.pipe(Schema.int(), Schema.between(1, 31)))
  ),
  monthly_goal: Schema.optional(Schema.NullOr(Schema.Number.pipe(Schema.greaterThan(0)))),
});

/**
 * Schema for Wage Snapshot
 */
const WageSnapshotSchema = Schema.Struct({
  id: Schema.UUID,
  user_id: Schema.UUID,
  from_date: Schema.NullOr(ISODateSchema),
  hourly_wage: Schema.Number.pipe(
    Schema.greaterThan(0),
    Schema.annotations({
      message: () => "Hourly wage must be positive",
    })
  ),
  wage_level: Schema.NullOr(Schema.Number.pipe(Schema.int(), Schema.between(-2, 9))),
  supplements: Schema.Struct({
    rules: Schema.Array(SupplementRuleSchema),
  }),
  created_at: Schema.optional(Schema.String),
});

/**
 * Validate shift input data
 */
export const validateShiftRow = (
  shift: unknown
): Effect.Effect<ShiftRow, ValidationError, never> =>
  Schema.decodeUnknown(ShiftRowSchema)(shift).pipe(
    Effect.map((validated) => validated as unknown as ShiftRow),
    Effect.mapError((parseError) => {
      const formatted = ParseResult.TreeFormatter.formatErrorSync(parseError);
      return new ValidationError({
        field: "shift",
        message: `Invalid shift data: ${formatted}`,
        cause: parseError,
      });
    })
  );

/**
 * Validate user settings
 */
export const validateUserSettings = (
  settings: unknown
): Effect.Effect<UserSettings, ValidationError, never> =>
  Schema.decodeUnknown(UserSettingsSchema)(settings).pipe(
    Effect.map((validated) => validated as unknown as UserSettings),
    Effect.mapError((parseError) => {
      const formatted = ParseResult.TreeFormatter.formatErrorSync(parseError);
      return new ValidationError({
        field: "settings",
        message: `Invalid user settings: ${formatted}`,
        cause: parseError,
      });
    })
  );

/**
 * Validate wage snapshot
 */
export const validateWageSnapshot = (
  snapshot: unknown
): Effect.Effect<WageSnapshot, ValidationError, never> =>
  Schema.decodeUnknown(WageSnapshotSchema)(snapshot).pipe(
    Effect.map((validated) => validated as unknown as WageSnapshot),
    Effect.mapError((parseError) => {
      const formatted = ParseResult.TreeFormatter.formatErrorSync(parseError);
      return new ValidationError({
        field: "wageSnapshot",
        message: `Invalid wage snapshot: ${formatted}`,
        cause: parseError,
      });
    })
  );

/**
 * Validate supplement rules array
 */
export const validateSupplementRules = (
  rules: unknown
): Effect.Effect<SupplementRule[], ValidationError, never> =>
  Schema.decodeUnknown(Schema.Array(SupplementRuleSchema))(rules).pipe(
    Effect.map((validated) => validated as unknown as SupplementRule[]),
    Effect.mapError((parseError) => {
      const formatted = ParseResult.TreeFormatter.formatErrorSync(parseError);
      return new ValidationError({
        field: "supplementRules",
        message: `Invalid supplement rules: ${formatted}`,
        cause: parseError,
      });
    })
  );

/**
 * Compute shift with Effect-based validation
 *
 * This wraps the pure computeShift function with validation and error handling.
 * The actual calculation logic remains unchanged - this just adds type safety.
 *
 * @param shift - Shift data to compute
 * @param settings - User settings for break calculations
 * @param presetRules - Preset supplement rules (fallback)
 * @param snapshot - Wage snapshot for historical accuracy
 * @returns Effect with computed shift data or validation error
 */
export const computeShift = (
  shift: ShiftRow,
  settings: UserSettings,
  presetRules: SupplementRule[],
  snapshot: WageSnapshot | null = null
): Effect.Effect<ShiftComputed, ValidationError, never> =>
  Effect.gen(function* () {
    // Validate inputs
    const validatedShift = yield* validateShiftRow(shift);
    const validatedSettings = yield* validateUserSettings(settings);
    const validatedRules = yield* validateSupplementRules(presetRules);
    const validatedSnapshot = snapshot
      ? yield* validateWageSnapshot(snapshot)
      : null;

    // Perform pure calculation
    const result = yield* Effect.try({
      try: () =>
        computeShiftPure(
          validatedShift,
          validatedSettings,
          validatedRules,
          validatedSnapshot
        ),
      catch: (error) =>
        new ValidationError({
          field: "computation",
          message: `Shift computation failed: ${String(error)}`,
          cause: error,
        }),
    });

    return result;
  });

/**
 * Compute multiple shifts in parallel
 *
 * Uses Effect.all for concurrent computation with controlled concurrency.
 * This is significantly faster than sequential computation for large batches.
 *
 * @param shifts - Array of shift data
 * @param settings - User settings
 * @param presetRules - Preset supplement rules
 * @param snapshots - Map of date to wage snapshot (for efficient lookup)
 * @param concurrency - Max concurrent computations ("unbounded" or number)
 * @returns Effect with array of computed shifts
 */
export const computeShifts = (
  shifts: ShiftRow[],
  settings: UserSettings,
  presetRules: SupplementRule[],
  snapshots: Map<string, WageSnapshot> | null = null,
  concurrency: "unbounded" | number = "unbounded"
): Effect.Effect<ShiftComputed[], ValidationError, never> =>
  Effect.all(
    shifts.map((shift) => {
      const snapshot = snapshots?.get(shift.shift_date) ?? null;
      return computeShift(shift, settings, presetRules, snapshot);
    }),
    { concurrency }
  );

/**
 * Validate time format (HH:MM)
 *
 * Standalone validator for use in server actions and forms
 */
export const validateTimeFormat = (time: string): Effect.Effect<HHMM, ValidationError, never> =>
  Schema.decodeUnknown(HHMMSchema)(time).pipe(
    Effect.map((validated) => validated as unknown as HHMM),
    Effect.mapError((parseError) => {
      const formatted = ParseResult.TreeFormatter.formatErrorSync(parseError);
      return new ValidationError({
        field: "time",
        message: formatted,
        cause: parseError,
      });
    })
  );

/**
 * Validate date format (YYYY-MM-DD)
 *
 * Standalone validator for use in server actions and forms
 */
export const validateDateFormat = (
  date: string
): Effect.Effect<string, ValidationError, never> =>
  Schema.decodeUnknown(ISODateSchema)(date).pipe(
    Effect.mapError((parseError) => {
      const formatted = ParseResult.TreeFormatter.formatErrorSync(parseError);
      return new ValidationError({
        field: "date",
        message: formatted,
        cause: parseError,
      });
    })
  );

/**
 * Check if shift crosses midnight (end_time <= start_time)
 */
export const crossesMidnight = (shift: ShiftRow): boolean => {
  return shift.end_time <= shift.start_time;
};

/**
 * Calculate shift duration in hours
 * Handles cross-midnight shifts correctly
 */
export const calculateDuration = (
  shift: ShiftRow
): Effect.Effect<number, ValidationError, never> =>
  Effect.gen(function* () {
    yield* validateTimeFormat(shift.start_time);
    yield* validateTimeFormat(shift.end_time);

    const [startHour, startMin] = shift.start_time.split(":").map(Number);
    const [endHour, endMin] = shift.end_time.split(":").map(Number);

    const startMinutes = startHour * 60 + startMin;
    let endMinutes = endHour * 60 + endMin;

    // Handle cross-midnight shifts
    if (endMinutes <= startMinutes) {
      endMinutes += 24 * 60; // Add 24 hours
    }

    const durationMinutes = endMinutes - startMinutes;
    return durationMinutes / 60;
  });

/**
 * Export schemas for use in other modules
 */
export const schemas = {
  ShiftRow: ShiftRowSchema,
  UserSettings: UserSettingsSchema,
  WageSnapshot: WageSnapshotSchema,
  SupplementRule: SupplementRuleSchema,
  HHMM: HHMMSchema,
  ISODate: ISODateSchema,
  BreakMethod: BreakMethodSchema,
};
