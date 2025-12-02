import { buildWagePeriods } from "./periods";
import { applyBreakDeduction } from "./breaks";
import {
  SupplementRule, ShiftComputed, ShiftRow, UserSettings, WagePeriod, BreakMethod, WageSnapshot, CustomSupplementsData
} from "./types";

const WEEKDAYS = [7,1,2,3,4,5,6]; // JS getDay(): 0=Sun → 7, then 1..6 Mon..Sat
export const PRESET_WAGE_RATES: Record<string, number> = {
  "-1": 129.91, "-2": 132.90, "1": 184.54, "2": 185.38,
  "3": 187.46, "4": 193.05, "5": 210.81, "6": 256.14,
};

const defaultSettings = {
  pause_deduction_enabled: true,
  pause_deduction_method: "proportional" as BreakMethod,
  pause_threshold_hours: 5.5,
  pause_deduction_minutes: 30,
};

/**
 * Resolve the base hourly wage rate for a shift
 * Priority order:
 * 1. New wage snapshot system (if provided)
 * 2. Old per-shift snapshot (for backward compatibility)
 * 3. Fallback to default rate (should never happen if snapshots are properly set up)
 */
function resolveBaseRate(
  s: ShiftRow,
  snapshot: WageSnapshot | null,
): number {
  // Priority 1: Use new snapshot system
  if (snapshot?.hourly_wage && snapshot.hourly_wage > 0) {
    return snapshot.hourly_wage;
  }

  // Priority 2: Backward compatibility - old per-shift snapshot
  if (s.hourly_wage_snapshot && s.hourly_wage_snapshot > 0) {
    return s.hourly_wage_snapshot;
  }

  // Priority 3: Fallback (should only happen if snapshot system is not configured)
  // This is a safety net - all users should have at least a baseline snapshot
  return PRESET_WAGE_RATES["1"];
}

/**
 * Resolve supplement rules with custom supplements
 *
 * When custom supplements exist, they completely replace predefined rules.
 * The custom supplements array already contains ALL supplements the user wants
 * (both kept tariff supplements and custom-added ones).
 *
 * @param weekday - Weekday of the shift (1-7)
 * @param predefinedRules - Rules from snapshot or preset
 * @param customSupplements - Shift-specific custom supplements
 * @returns Final supplement rules to use
 */
function resolveSupplementRules(
  weekday: number,
  predefinedRules: SupplementRule[],
  customSupplements: CustomSupplementsData | null | undefined
): SupplementRule[] {
  if (!customSupplements || !customSupplements.rules || customSupplements.rules.length === 0) {
    return predefinedRules;
  }

  // Custom supplements completely replace predefined rules
  // Convert custom supplement rules to full SupplementRule format (add days field)
  return customSupplements.rules.map(rule => ({
    ...rule,
    days: [weekday], // Apply to this shift's weekday only
  }));
}

// Precision constants for payroll calculations
const HOUR_DECIMAL_PRECISION = 1000; // 3 decimal places (0.001 hours)
const CURRENCY_PRECISION = 100; // 2 decimal places (cents)

/**
 * Compute payroll for a single shift
 *
 * @param shift - The shift data
 * @param settings - User's current settings (for break deduction settings)
 * @param presetRules - Preset supplement rules (fallback if no snapshot)
 * @param snapshot - Wage snapshot for historical accuracy (should always be provided)
 * @returns Computed payroll data including gross pay, hours, and breakdown
 */
export function computeShift(
  shift: ShiftRow,
  settings: UserSettings,
  presetRules: SupplementRule[],
  snapshot: WageSnapshot | null = null
): ShiftComputed {
  const s = { ...shift };
  const st = s.start_time;
  const et = s.end_time;

  const date = new Date(s.shift_date + "T00:00:00Z");
  const weekday = WEEKDAYS[date.getUTCDay()]; // 1-7

  const baseRate = resolveBaseRate(s, snapshot);

  // Supplement rules resolution priority:
  // 1. New snapshot system (if provided) - use rules even if empty (user explicitly has no supplements)
  // 2. Old per-shift snapshot (backward compatibility)
  // 3. Fallback to preset rules (should never happen if snapshots are properly set up)
  const predefinedRules: SupplementRule[] = snapshot?.supplements?.rules
    ? snapshot.supplements.rules
    : s.supplement_rules_snapshot?.rules
    ? s.supplement_rules_snapshot.rules
    : presetRules;

  // Apply custom supplements (merge or replace based on mode)
  const rules = resolveSupplementRules(weekday, predefinedRules, s.custom_supplements);

  let periods: WagePeriod[] = buildWagePeriods(st, et, weekday, baseRate, rules);

  // duration
  const totalMinutes = periods.reduce((sum, p) => sum + (p.toMin - p.fromMin), 0);
  const durationHours = +(totalMinutes / 60).toFixed(2);

  // Store original periods before break deduction (for display purposes)
  const originalWagePeriods = periods.map(p => ({ ...p }));

  // Resolve break settings - support both old and new field names
  const pauseEnabled =
    settings.pause_deduction_enabled ??
    defaultSettings.pause_deduction_enabled;
  const method =
    settings.pause_deduction_method ??
    defaultSettings.pause_deduction_method;
  const threshold =
    settings.pause_threshold_hours ??
    defaultSettings.pause_threshold_hours;
  const pauseMinutes = pauseEnabled
    ? settings.pause_deduction_minutes ??
      defaultSettings.pause_deduction_minutes
    : 0;
  const pauseHours = pauseMinutes / 60;

  // Apply automatic break deduction
  const afterBreak = applyBreakDeduction(periods, method, threshold, pauseHours);
  periods = afterBreak.periods;

  const paidMinutes = periods.reduce((sum, p) => sum + (p.toMin - p.fromMin), 0);
  const paidHours = +(paidMinutes / 60).toFixed(2);

  // pay
  let basePay = 0, supplementPay = 0;
  for (const p of periods) {
    // Round hours to 3 decimals to match old codebase behavior
    const h = Math.round((p.toMin - p.fromMin) / 60 * HOUR_DECIMAL_PRECISION) / HOUR_DECIMAL_PRECISION;
    // Round each period's contribution to cents
    basePay += Math.round(h * p.baseRate * CURRENCY_PRECISION) / CURRENCY_PRECISION;
    supplementPay += Math.round(h * p.supplementRate * CURRENCY_PRECISION) / CURRENCY_PRECISION;
  }
  basePay = +basePay.toFixed(2);
  supplementPay = +supplementPay.toFixed(2);
  const gross = +(basePay + supplementPay).toFixed(2);

  return {
    id: s.id,
    durationHours,
    paidHours,
    basePay,
    supplementPay,
    gross,
    wagePeriods: periods,
    originalWagePeriods,
    breakAudit: afterBreak.audit
  };
}
