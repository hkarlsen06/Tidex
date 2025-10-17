import { buildWagePeriods } from "./periods";
import { applyBreakDeduction } from "./breaks";
import {
  BonusRule, ShiftComputed, ShiftRow, UserSettings, WagePeriod, BreakMethod
} from "./types";

const WEEKDAYS = [7,1,2,3,4,5,6]; // JS getDay(): 0=Sun → 7, then 1..6 Mon..Sat
export const PRESET_WAGE_RATES: Record<string, number> = {
  "-1": 129.91, "-2": 132.90, "1": 184.54, "2": 185.38,
  "3": 187.46, "4": 193.05, "5": 210.81, "6": 256.14,
};

const defaultSettings = {
  break_enabled: true,
  break_method: "proportional" as BreakMethod,
  break_threshold_hours: 5.5,
  break_deduction_minutes: 30,
};

function resolveBaseRate(s: ShiftRow, settings: UserSettings): number {
  if (s.hourly_wage_snapshot && s.hourly_wage_snapshot > 0) return s.hourly_wage_snapshot;
  if (settings.use_preset && settings.current_wage_level != null) {
    const key = String(settings.current_wage_level);
    if (PRESET_WAGE_RATES[key] != null) return PRESET_WAGE_RATES[key];
  }
  if (settings.custom_wage && settings.custom_wage > 0) return settings.custom_wage;
  return PRESET_WAGE_RATES["1"]; // sane fallback
}

// Precision constants for payroll calculations
const HOUR_DECIMAL_PRECISION = 1000; // 3 decimal places (0.001 hours)
const CURRENCY_PRECISION = 100; // 2 decimal places (cents)

export function computeShift(
  shift: ShiftRow,
  settings: UserSettings,
  presetRules: BonusRule[]
): ShiftComputed {
  const s = { ...shift };
  const st = s.start_time;
  const et = s.end_time;

  const date = new Date(s.shift_date + "T00:00:00Z");
  const weekday = WEEKDAYS[date.getUTCDay()]; // 1-7

  const baseRate = resolveBaseRate(s, settings);
  const rules: BonusRule[] = settings.use_preset
    ? presetRules
    : (settings.custom_bonuses?.rules?.length ? settings.custom_bonuses.rules : []);

  let periods: WagePeriod[] = buildWagePeriods(st, et, weekday, baseRate, rules);

  // duration
  const totalMinutes = periods.reduce((sum, p) => sum + (p.toMin - p.fromMin), 0);
  const durationHours = +(totalMinutes / 60).toFixed(2);

  // Store original periods before break deduction (for display purposes)
  const originalWagePeriods = periods.map(p => ({ ...p }));

  // Resolve break settings - support both old and new field names
  const breakEnabled = settings.break_enabled ?? settings.pause_deduction_enabled ?? defaultSettings.break_enabled;
  const method = settings.break_method ?? settings.pause_deduction_method ?? defaultSettings.break_method;
  const threshold = settings.break_threshold_hours ?? settings.pause_threshold_hours ?? defaultSettings.break_threshold_hours;
  const breakMinutes = breakEnabled ? (settings.break_deduction_minutes ?? settings.pause_deduction_minutes ?? defaultSettings.break_deduction_minutes) : 0;
  const breakHours = breakMinutes / 60;

  // Apply automatic break deduction
  const afterBreak = applyBreakDeduction(periods, method, threshold, breakHours);
  periods = afterBreak.periods;

  const paidMinutes = periods.reduce((sum, p) => sum + (p.toMin - p.fromMin), 0);
  const paidHours = +(paidMinutes / 60).toFixed(2);

  // pay
  let basePay = 0, bonusPay = 0;
  for (const p of periods) {
    // Round hours to 3 decimals to match old codebase behavior
    const h = Math.round((p.toMin - p.fromMin) / 60 * HOUR_DECIMAL_PRECISION) / HOUR_DECIMAL_PRECISION;
    // Round each period's contribution to cents
    basePay += Math.round(h * p.baseRate * CURRENCY_PRECISION) / CURRENCY_PRECISION;
    bonusPay += Math.round(h * p.bonusRate * CURRENCY_PRECISION) / CURRENCY_PRECISION;
  }
  basePay = +basePay.toFixed(2);
  bonusPay = +bonusPay.toFixed(2);
  const gross = +(basePay + bonusPay).toFixed(2);

  return {
    id: s.id,
    durationHours,
    paidHours,
    basePay,
    bonusPay,
    gross,
    wagePeriods: periods,
    originalWagePeriods,
    breakAudit: afterBreak.audit
  };
}
