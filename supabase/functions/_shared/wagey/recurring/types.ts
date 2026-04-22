/**
 * Recurring shifts types for recurring shift patterns
 *
 * A recurring shift defines a pattern of recurring shifts based on:
 * - Selected weekday anchors (up to 7, one per weekday)
 * - Repetition interval in weeks (0 = every week, 1 = every 2 weeks, etc.)
 * - End condition (null = no end, or duration/end date)
 * - Exclusions (individual dates to skip)
 */

import type { CustomPauseWindows, CustomSupplementsData } from "../payroll/types.ts";

/**
 * End condition for a recurring shift
 * - null: No end date (continues indefinitely, UI shows preview for 6 months)
 * - months: Duration in months from the earliest anchor
 * - years: Duration in years from the earliest anchor
 * - end_date: Specific end date with optional time (defaults to 23:59:59)
 *
 * Note: The end_date type supports two formats for backward compatibility:
 * - Newer format: { type: 'end_date'; date: string; end_time?: string }
 * - Legacy format: { type: 'end_date'; value: string }
 */
export type EndCondition =
  | null
  | { type: 'months'; value: number }
  | { type: 'years'; value: number }
  | { type: 'end_date'; date: string; end_time?: string }
  | { type: 'end_date'; value: string }; // Legacy format - some DB records use 'value' instead of 'date'

/**
 * Selected anchor dates by weekday
 * Key: '0' (Sunday) through '6' (Saturday)
 * Value: ISO date string (YYYY-MM-DD) of the anchor date
 *
 * Example: { "1": "2025-10-27", "3": "2025-10-29" }
 * means Monday anchored at Oct 27, Wednesday at Oct 29
 */
export type SelectedDays = Partial<Record<'0' | '1' | '2' | '3' | '4' | '5' | '6', string>>;

/**
 * Local draft state for recurring shift form
 * Persisted to localStorage as user builds their recurring shift
 */
export type RecurringDraft = {
  /** Start time in HH:mm format (e.g., '08:00') - will be converted to timetz on server */
  start_time: string;
  /** End time in HH:mm format (e.g., '16:00') - will be converted to timetz on server */
  end_time: string;
  /** Repetition interval: 0 = every week, 1 = every 2 weeks, up to 8 = every 9 weeks */
  repeat_interval_weeks: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
  /** Anchor dates selected by the user, keyed by weekday (0-6) */
  selected_days: SelectedDays;
  /** When the recurring shift should end (null = no end) */
  end_condition: EndCondition;
  /** Individual dates to exclude from the recurring shift (ISO date strings) */
  exclusions: string[];
};

/**
 * A "virtual shift" is a projected occurrence of a shift in the recurring pattern.
 * Virtual shifts are computed at runtime and not stored in the database.
 * Displayed on the calendar to preview the recurring pattern.
 */
export type RecurringVirtualShift = {
  /** ISO date of the projected shift */
  date: string;
  /** Weekday (0-6) for quick filtering/grouping */
  weekday: number;
  /** Computed earnings preview (optional, calculated from start/end time) */
  earnings?: number;
};

/**
 * Database row shape for recurring_shifts table
 * Maps to the Supabase table schema
 */
export type RecurringShiftRow = {
  id: string;
  user_id: string;
  /** Start time with timezone (timetz) */
  start_time: string;
  /** End time with timezone (timetz) */
  end_time: string;
  /** Week interval (0-8) */
  repeat_interval_weeks: number;
  /** Anchor dates by weekday (JSONB) */
  selected_days: SelectedDays;
  /** End condition (JSONB, nullable) */
  end_condition: EndCondition;
  /** Excluded dates (JSONB array) */
  exclusions: string[];
  /** Date-specific pause overrides (JSONB, nullable) */
  date_specific_pause_windows?: DateSpecificPauseWindows | null;
  /** Date-specific supplement overrides (JSONB, nullable) */
  date_specific_supplements?: DateSpecificSupplements | null;
  created_at?: string;
  updated_at?: string;
};

/**
 * Date-specific supplement overrides for recurring shifts
 * Key: ISO date string (YYYY-MM-DD)
 * Value: Custom supplement data for that specific date
 *
 * When present, these rules REPLACE all tariff supplements for that date.
 * The rules array contains ALL supplements the user wants for that occurrence.
 */
export type DateSpecificSupplements = {
  [isoDate: string]: CustomSupplementsData;
};

export type DateSpecificPauseWindows = {
  [isoDate: string]: CustomPauseWindows;
};

/**
 * Date window for calendar navigation
 * Calculated from anchors and end_condition
 */
export type DateWindow = {
  /** Earliest month that can contain anchors/virtual shifts */
  minMonth: Date;
  /** Latest month that can contain anchors/virtual shifts */
  maxMonth: Date;
  /** Actual maximum date (inclusive) for virtual shift generation */
  maxDate: Date;
};
