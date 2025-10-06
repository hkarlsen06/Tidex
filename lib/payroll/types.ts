export type HHMM = `${number}:${number}`;

export type ShiftRow = {
  id: string;
  user_id: string;
  shift_date: string;           // ISO date
  start_time: string;           // "HH:mm"
  end_time: string;             // "HH:mm"
  pause_duration_hours?: number | null;
  hourly_wage_snapshot?: number | null; // optional if you snapshot on insert
};

export type UserSettings = {
  use_preset?: boolean | null;
  custom_wage?: number | null;
  current_wage_level?: number | null; // maps to preset table
  custom_bonuses?: { rules: BonusRule[] } | null;

  // Break/pause settings (support both old and new field names for backward compatibility)
  break_enabled?: boolean | null;          // Master switch for automatic break deductions
  break_method?: BreakMethod | null;       // How to apply deduction (proportional, base_only, end_of_shift)
  break_threshold_hours?: number | null;   // Minimum shift duration to trigger break (e.g., 5.5)
  break_deduction_minutes?: number | null; // Amount to deduct (e.g., 30)

  // Old field names (deprecated but supported)
  pause_deduction_enabled?: boolean | null;
  pause_deduction_method?: BreakMethod | null;
  pause_threshold_hours?: number | null;
  pause_deduction_minutes?: number | null;

  audit_break_calculations?: boolean | null;
};

export type BonusRule = {
  days: number[];   // 1-7 Mon..Sun
  from: HHMM;       // inclusive
  to: HHMM;         // inclusive
  rate?: number;    // Fixed NOK per hour supplement (e.g., 22, 45, 110)
  percent?: number; // Percentage supplement (e.g., 50 for 50% bonus)
};

export type BreakMethod = "proportional" | "base_only" | "end_of_shift" | "none";

export type WagePeriod = {
  fromMin: number;
  toMin: number; // exclusive
  baseRate: number;
  bonusRate: number; // supplement per hour
  totalRate: number; // base + bonus
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
  bonusPay: number;              // NOK
  gross: number;                 // NOK
  wagePeriods: WagePeriod[];     // after split
  breakAudit: BreakAudit;
};

export type ShiftWithComputations = ShiftRow & {
  computed: ShiftComputed;
};
