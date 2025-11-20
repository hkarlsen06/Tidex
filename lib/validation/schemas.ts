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
import { ValidationError } from "../errors/tagged";

/**
 * ISO Date format (YYYY-MM-DD)
 * @example "2025-01-15"
 */
export const ISODateString = Schema.String.pipe(
  Schema.pattern(/^\d{4}-\d{2}-\d{2}$/),
  Schema.brand("ISODateString")
);

export type ISODateString = typeof ISODateString.Type;

/**
 * Time format (HH:MM)
 * @example "14:30", "09:00"
 */
export const TimeString = Schema.String.pipe(
  Schema.pattern(/^\d{2}:\d{2}$/),
  Schema.brand("TimeString")
);

export type TimeString = typeof TimeString.Type;

/**
 * Positive number
 */
export const PositiveNumber = Schema.Number.pipe(
  Schema.positive(),
  Schema.brand("PositiveNumber")
);

export type PositiveNumber = typeof PositiveNumber.Type;

/**
 * Non-negative number (>= 0)
 */
export const NonNegativeNumber = Schema.Number.pipe(
  Schema.nonNegative(),
  Schema.brand("NonNegativeNumber")
);

export type NonNegativeNumber = typeof NonNegativeNumber.Type;

/**
 * Hourly wage (positive number, max 9999 for database limits)
 */
export const HourlyWage = Schema.Number.pipe(
  Schema.positive(),
  Schema.lessThanOrEqualTo(9999),
  Schema.brand("HourlyWage")
);

export type HourlyWage = typeof HourlyWage.Type;

/**
 * Hours worked (0-24 for single shift)
 */
export const HoursWorked = Schema.Number.pipe(
  Schema.nonNegative(),
  Schema.lessThanOrEqualTo(24),
  Schema.brand("HoursWorked")
);

export type HoursWorked = typeof HoursWorked.Type;

/**
 * Tax percentage (0-100)
 */
export const TaxPercentage = Schema.Number.pipe(
  Schema.between(0, 100),
  Schema.brand("TaxPercentage")
);

export type TaxPercentage = typeof TaxPercentage.Type;

/**
 * UUID string
 */
export const UUIDString = Schema.String.pipe(
  Schema.pattern(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  ),
  Schema.brand("UUIDString")
);

export type UUIDString = typeof UUIDString.Type;

/**
 * Shift type enum
 */
export const ShiftType = Schema.Literal("single", "series");
export type ShiftType = typeof ShiftType.Type;

/**
 * Pause deduction method enum
 */
export const PauseDeductionMethod = Schema.Literal(
  "none",
  "fixed",
  "proportional",
  "threshold"
);
export type PauseDeductionMethod = typeof PauseDeductionMethod.Type;

/**
 * Shift validation schema (for create/update operations)
 */
export const ShiftInput = Schema.Struct({
  date: ISODateString,
  start: TimeString,
  end: TimeString,
  hourly_wage: Schema.optional(HourlyWage),
  description: Schema.optional(Schema.String),
  shift_type: Schema.optional(ShiftType),
});

export type ShiftInput = typeof ShiftInput.Type;

/**
 * Settings update schema (partial updates allowed)
 */
export const SettingsUpdate = Schema.Struct({
  theme: Schema.optional(Schema.String),
  default_shifts_view: Schema.optional(Schema.String),
  direct_time_input: Schema.optional(Schema.Boolean),
  use_preset: Schema.optional(Schema.Boolean),
  current_wage_level: Schema.optional(Schema.Number),
  custom_wage: Schema.optional(Schema.NullOr(HourlyWage)),
  tax_deduction_enabled: Schema.optional(Schema.Boolean),
  tax_percentage: Schema.optional(Schema.NullOr(TaxPercentage)),
  monthly_goal: Schema.optional(Schema.NullOr(PositiveNumber)),
});

export type SettingsUpdate = typeof SettingsUpdate.Type;

/**
 * Helper to validate ISO date string
 */
export const validateISODate = (input: string) =>
  Schema.decodeUnknown(ISODateString)(input);

/**
 * Helper to validate time string
 */
export const validateTime = (input: string) =>
  Schema.decodeUnknown(TimeString)(input);

/**
 * Helper to validate shift input
 */
export const validateShiftInput = (input: unknown) =>
  Schema.decodeUnknown(ShiftInput)(input);

/**
 * Helper to validate settings update
 */
export const validateSettingsUpdate = (input: unknown) =>
  Schema.decodeUnknown(SettingsUpdate)(input);
