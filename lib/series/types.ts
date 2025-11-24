/**
 * Series shifts types for recurring shift patterns
 *
 * A series shift defines a pattern of recurring shifts based on:
 * - Selected weekday anchors (up to 7, one per weekday)
 * - Repetition interval in weeks (0 = every week, 1 = every 2 weeks, etc.)
 * - End condition (null = no end, or duration/end date)
 * - Exclusions (individual dates to skip)
 */

/**
 * End condition for a series
 * - null: No end date (continues indefinitely, UI shows preview for 6 months)
 * - months: Duration in months from the earliest anchor
 * - years: Duration in years from the earliest anchor
 * - end_date: Specific end date with optional time (defaults to 23:59:59)
 */
export type EndCondition =
  | null
  | { type: 'months'; value: number }
  | { type: 'years'; value: number }
  | { type: 'end_date'; date: string; end_time?: string };

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
 * Local draft state for series shift form
 * Persisted to localStorage as user builds their series
 */
export type SeriesDraft = {
  /** Start time in HH:mm format (e.g., '08:00') - will be converted to timetz on server */
  start_time: string;
  /** End time in HH:mm format (e.g., '16:00') - will be converted to timetz on server */
  end_time: string;
  /** Repetition interval: 0 = every week, 1 = every 2 weeks, up to 8 = every 9 weeks */
  repeat_interval_weeks: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
  /** Anchor dates selected by the user, keyed by weekday (0-6) */
  selected_days: SelectedDays;
  /** When the series should end (null = no end) */
  end_condition: EndCondition;
  /** Individual dates to exclude from the series (ISO date strings) */
  exclusions: string[];
};

/**
 * A "ghost" is a projected occurrence of a shift in the series
 * Displayed on the calendar to preview the series pattern
 */
export type SeriesGhost = {
  /** ISO date of the projected shift */
  date: string;
  /** Weekday (0-6) for quick filtering/grouping */
  weekday: number;
  /** Computed earnings preview (optional, calculated from start/end time) */
  earnings?: number;
};

/**
 * Database row shape for series_shifts table
 * Maps to the Supabase table schema
 */
export type SeriesShiftRow = {
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
  /** Date-specific supplement overrides (JSONB, nullable) */
  date_specific_supplements?: DateSpecificSupplements | null;
  created_at?: string;
  updated_at?: string;
};

/**
 * Date-specific supplement overrides for series shifts
 * Key: ISO date string (YYYY-MM-DD)
 * Value: Custom supplement data for that specific date
 */
export type DateSpecificSupplements = {
  [isoDate: string]: {
    mode: 'replace' | 'merge';
    rules: Array<{
      from: string;    // HHMM format
      to: string;      // HHMM format
      rate?: number;
      percent?: number;
    }>;
  };
};

/**
 * Date window for calendar navigation
 * Calculated from anchors and end_condition
 */
export type DateWindow = {
  /** Earliest month that can contain anchors/ghosts */
  minMonth: Date;
  /** Latest month that can contain anchors/ghosts */
  maxMonth: Date;
  /** Actual maximum date (inclusive) for ghost generation */
  maxDate: Date;
};
