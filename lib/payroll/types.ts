export type HHMM = `${number}:${number}`;

export type ShiftRow = {
  id: string;
  user_id: string;
  shift_date: string;           // ISO date
  start_time: string;           // "HH:mm"
  end_time: string;             // "HH:mm"
  hourly_wage_snapshot?: number | null; // Snapshot of hourly wage at creation time
  supplement_rules_snapshot?: { rules: SupplementRule[] } | null; // Snapshot of supplement rules at creation time
  custom_supplements?: CustomSupplementsData | null; // Shift-specific supplement overrides
  series_id?: string;           // Links to series_shifts if this is a ghost
  series_anchor_weekday?: number; // Which weekday anchor (0-6) generated this ghost
};

/**
 * Custom supplement data for a shift
 */
export type CustomSupplementsData = {
  mode: 'replace' | 'merge';
  rules: Omit<SupplementRule, 'days'>[]; // No days field since it applies to one specific day
};

export type UserSettings = {
  // NOTE: Wage-related fields (use_preset, custom_wage, current_wage_level, custom_supplements)
  // have been removed. Wage data is now stored in the wage_snapshots table.
  // See migration: 20251101130000_remove_wage_from_user_settings.sql

  // Pause settings
  pause_deduction_enabled?: boolean | null; // Master switch for automatic break deductions
  pause_deduction_method?: BreakMethod | null; // How to apply deduction (proportional, base_only, end_of_shift)
  pause_threshold_hours?: number | null; // Minimum shift duration to trigger break (e.g., 5.5)
  pause_deduction_minutes?: number | null; // Amount to deduct (e.g., 30)

  // Tax settings
  tax_deduction_enabled?: boolean | null;
  tax_percentage?: number | null;
  half_tax_month?: number | null; // Month number (11=November, 12=December) for half tax deduction
  payroll_day?: number | null;
  monthly_goal?: number | null;
};

export type SupplementRule = {
  days: number[];   // 1-7 Mon..Sun
  from: HHMM;       // inclusive
  to: HHMM;         // inclusive
  rate?: number;    // Fixed NOK per hour supplement (e.g., 22, 45, 110)
  percent?: number; // Percentage supplement (e.g., 50 for 50% supplement)
};

export type BreakMethod = "proportional" | "base_only" | "end_of_shift" | "none";

export type WagePeriod = {
  fromMin: number;
  toMin: number; // exclusive
  baseRate: number;
  supplementRate: number; // supplement per hour
  totalRate: number; // base + supplement
};

export type BreakAudit = {
  method: BreakMethod;
  thresholdHours: number;
  deductedHours: number;
  notes?: string[];
};

export type ShiftComputed = {
  id: string;
  durationHours: number;         // raw
  paidHours: number;             // after break
  basePay: number;               // NOK
  supplementPay: number;              // NOK
  gross: number;                 // NOK
  wagePeriods: WagePeriod[];     // after break deduction
  originalWagePeriods: WagePeriod[]; // before break deduction (for display)
  breakAudit: BreakAudit;
};

export type ShiftWithComputations = ShiftRow & {
  computed: ShiftComputed;
};

/**
 * WageSnapshot from the wage_snapshots table
 * Represents a point-in-time capture of wage and supplement settings
 *
 * Note: from_date can be NULL for the baseline snapshot, which serves as
 * the fallback for all shifts that don't match any dated snapshot
 */
export type WageSnapshot = {
  id: string;
  user_id: string;
  from_date: string | null; // ISO date (YYYY-MM-DD) or NULL for baseline
  hourly_wage: number;
  wage_level: number | null; // NULL = custom wage, NUMBER (1-9) = tariff level
  supplements: { rules: SupplementRule[] };
  created_at?: string;
};
