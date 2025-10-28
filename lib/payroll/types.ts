export type HHMM = `${number}:${number}`;

export type ShiftRow = {
  id: string;
  user_id: string;
  shift_date: string;           // ISO date
  start_time: string;           // "HH:mm"
  end_time: string;             // "HH:mm"
  hourly_wage_snapshot?: number | null; // Snapshot of hourly wage at creation time
  supplement_rules_snapshot?: { rules: SupplementRule[] } | null; // Snapshot of supplement rules at creation time
  series_id?: string;           // Links to series_shifts if this is a ghost
  series_anchor_weekday?: number; // Which weekday anchor (0-6) generated this ghost
};

export type UserSettings = {
  use_preset?: boolean | null;
  custom_wage?: number | null;
  current_wage_level?: number | null; // maps to preset table
  custom_supplements?: { rules: SupplementRule[] } | null;

  // Pause settings
  pause_deduction_enabled?: boolean | null; // Master switch for automatic break deductions
  pause_deduction_method?: BreakMethod | null; // How to apply deduction (proportional, base_only, end_of_shift)
  pause_threshold_hours?: number | null; // Minimum shift duration to trigger break (e.g., 5.5)
  pause_deduction_minutes?: number | null; // Amount to deduct (e.g., 30)

  // Tax settings
  tax_deduction_enabled?: boolean | null;
  tax_percentage?: number | null;
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
