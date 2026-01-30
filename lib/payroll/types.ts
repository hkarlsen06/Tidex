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
  recurring_id?: string;           // Links to recurring_shifts if this is a virtual shift
  recurring_anchor_weekday?: number; // Which weekday anchor (0-6) generated this virtual shift
};

/**
 * A single supplement rule with origin tracking
 */
export type CustomSupplementRuleSaved = Omit<SupplementRule, 'days'> & {
  isCustom?: boolean; // true = user-added, false/undefined = from tariff
};

/**
 * Custom supplement data for a shift
 * When present, these rules REPLACE all tariff supplements for the shift.
 * The rules array contains ALL supplements the user wants for this shift.
 */
export type CustomSupplementsData = {
  rules: CustomSupplementRuleSaved[];
};

export type UserSettings = {
  // NOTE: Wage-related fields (use_preset, custom_wage, current_wage_level, custom_supplements)
  // have been removed. Wage data is now stored in the wage_snapshots table.
  // See migration: 20251101130000_remove_wage_from_user_settings.sql

  // NOTE: Tax and break deduction settings have been moved to wage_snapshots.
  // See migration: 20251215000000_move_tax_break_to_snapshots.sql

  // Global calendar preferences (not per-snapshot)
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
  /**
   * Tax settings from the snapshot that applies to this shift
   * Used for calculating after-tax earnings display
   */
  tax_enabled?: boolean;
  tax_percentage?: number;
};

/**
 * WageSnapshot from the wage_snapshots table
 * Represents a point-in-time capture of wage, supplement, tax, and break settings
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
  tariff_type_id: string | null; // e.g., "hk_retail", NULL for custom wage
  supplements: { rules: SupplementRule[] };
  created_at?: string;

  // Tax settings (per-snapshot)
  tax_enabled: boolean;
  tax_percentage: number;

  // Break deduction settings (per-snapshot)
  break_enabled: boolean;
  break_method: BreakMethod;
  break_threshold_hours: number;
  break_deduction_minutes: number;
};
