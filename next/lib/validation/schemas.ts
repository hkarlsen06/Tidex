/**
 * Validation Schemas with Effect Schema
 *
 * Provides composable, type-safe validation schemas for:
 * - Date and time formats
 * - Shift data
 * - User inputs
 *
 * All validators return Effect types with typed errors.
 */

import { Schema } from "effect";

/**
 * ISO Date format (YYYY-MM-DD)
 * @example "2025-01-15"
 */
export const ISODateStringSchema = Schema.String.pipe(
  Schema.pattern(/^\d{4}-\d{2}-\d{2}$/),
  Schema.brand("ISODateString")
);

export type ISODateString = typeof ISODateStringSchema.Type;

/**
 * Time format (HH:MM)
 * @example "14:30", "09:00"
 */
export const TimeStringSchema = Schema.String.pipe(
  Schema.pattern(/^\d{2}:\d{2}$/),
  Schema.brand("TimeString")
);

export type TimeString = typeof TimeStringSchema.Type;

/**
 * Positive number
 */
export const PositiveNumberSchema = Schema.Number.pipe(
  Schema.positive(),
  Schema.brand("PositiveNumber")
);

export type PositiveNumber = typeof PositiveNumberSchema.Type;

/**
 * Non-negative number (>= 0)
 */
export const NonNegativeNumberSchema = Schema.Number.pipe(
  Schema.nonNegative(),
  Schema.brand("NonNegativeNumber")
);

export type NonNegativeNumber = typeof NonNegativeNumberSchema.Type;

/**
 * Hourly wage (positive number, max 9999 for database limits)
 */
export const HourlyWageSchema = Schema.Number.pipe(
  Schema.positive(),
  Schema.lessThanOrEqualTo(9999),
  Schema.brand("HourlyWage")
);

export type HourlyWage = typeof HourlyWageSchema.Type;

/**
 * Hours worked (0-24 for single shift)
 */
export const HoursWorkedSchema = Schema.Number.pipe(
  Schema.nonNegative(),
  Schema.lessThanOrEqualTo(24),
  Schema.brand("HoursWorked")
);

export type HoursWorked = typeof HoursWorkedSchema.Type;

/**
 * Tax percentage (0-100)
 */
export const TaxPercentageSchema = Schema.Number.pipe(
  Schema.between(0, 100),
  Schema.brand("TaxPercentage")
);

export type TaxPercentage = typeof TaxPercentageSchema.Type;

/**
 * UUID string
 */
export const UUIDStringSchema = Schema.String.pipe(
  Schema.pattern(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  ),
  Schema.brand("UUIDString")
);

export type UUIDString = typeof UUIDStringSchema.Type;

/**
 * Shift type enum
 */
export const ShiftTypeSchema = Schema.Literal("single", "recurring");
export type ShiftType = typeof ShiftTypeSchema.Type;

/**
 * Pause deduction method enum
 */
export const PauseDeductionMethodSchema = Schema.Literal(
  "none",
  "fixed",
  "proportional",
  "threshold"
);
export type PauseDeductionMethod = typeof PauseDeductionMethodSchema.Type;

/**
 * Shift validation schema (for create/update operations)
 */
export const ShiftInputSchema = Schema.Struct({
  date: ISODateStringSchema,
  start: TimeStringSchema,
  end: TimeStringSchema,
  hourly_wage: Schema.optional(HourlyWageSchema),
  description: Schema.optional(Schema.String),
  shift_type: Schema.optional(ShiftTypeSchema),
});

export type ShiftInput = typeof ShiftInputSchema.Type;

/**
 * Settings update schema (partial updates allowed)
 */
export const SettingsUpdateSchema = Schema.Struct({
  theme: Schema.optional(Schema.String),
  default_shifts_view: Schema.optional(Schema.String),
  direct_time_input: Schema.optional(Schema.Boolean),
  use_preset: Schema.optional(Schema.Boolean),
  current_wage_level: Schema.optional(Schema.Number),
  custom_wage: Schema.optional(Schema.NullOr(HourlyWageSchema)),
  tax_deduction_enabled: Schema.optional(Schema.Boolean),
  tax_percentage: Schema.optional(Schema.NullOr(TaxPercentageSchema)),
  monthly_goal: Schema.optional(Schema.NullOr(PositiveNumberSchema)),
});

export type SettingsUpdate = typeof SettingsUpdateSchema.Type;

/**
 * Helper to validate ISO date string
 */
export const validateISODate = (input: string) =>
  Schema.decodeUnknown(ISODateStringSchema)(input);

/**
 * Helper to validate time string
 */
export const validateTime = (input: string) =>
  Schema.decodeUnknown(TimeStringSchema)(input);

/**
 * Helper to validate shift input
 */
export const validateShiftInput = (input: unknown) =>
  Schema.decodeUnknown(ShiftInputSchema)(input);

/**
 * Helper to validate settings update
 */
export const validateSettingsUpdate = (input: unknown) =>
  Schema.decodeUnknown(SettingsUpdateSchema)(input);
