import { buildWagePeriods } from "./periods";
import { applyBreakDeduction } from "./breaks";
import {
  BonusRule, ShiftComputed, ShiftRow, UserSettings, WagePeriod,
  BreakPolicy, BreakMethod
} from "./types";

const WEEKDAYS = [7,1,2,3,4,5,6]; // JS getDay(): 0=Sun → 7, then 1..6 Mon..Sat
const PRESET_WAGE_RATES: Record<string, number> = {
  "-1": 129.91, "-2": 132.90, "1": 184.54, "2": 185.38,
  "3": 187.46, "4": 193.05, "5": 210.81, "6": 256.14,
};

const defaultSettings = {
  break_policy: "fixed_0_5_over_5_5h" as BreakPolicy,
  pause_deduction_enabled: true,
  pause_deduction_method: "proportional" as BreakMethod,
  pause_threshold_hours: 5.5,
  pause_deduction_minutes: 30,
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
  const rules: BonusRule[] =
    settings.custom_bonuses?.rules?.length ? settings.custom_bonuses.rules : presetRules;

  let periods: WagePeriod[] = buildWagePeriods(st, et, weekday, baseRate, rules);

  // duration
  const totalMinutes = periods.reduce((sum, p) => sum + (p.toMin - p.fromMin), 0);
  const durationHours = +(totalMinutes / 60).toFixed(2);

  // manual pause (user-entered), treated as additional deduction
  const manualPauseHours = Math.max(0, s.pause_duration_hours ?? 0);

  const policy = settings.break_policy ?? defaultSettings.break_policy;
  const method = settings.pause_deduction_method ?? defaultSettings.pause_deduction_method;
  const threshold = settings.pause_threshold_hours ?? defaultSettings.pause_threshold_hours;
  const policyMinutes = settings.pause_deduction_enabled === false ? 0 : (settings.pause_deduction_minutes ?? defaultSettings.pause_deduction_minutes);
  const policyHours = policyMinutes / 60;

  // apply policy deduction first
  const afterPolicy = applyBreakDeduction(periods, policy, method, threshold, policyHours);
  periods = afterPolicy.periods;

  // then apply manual pause by subtracting from tail for determinism
  let remaining = Math.round(manualPauseHours * 60);
  for (let i = periods.length - 1; i >= 0 && remaining > 0; i--) {
    const span = periods[i].toMin - periods[i].fromMin;
    const cut = Math.min(span, remaining);
    periods[i].toMin -= cut;
    remaining -= cut;
  }
  periods = periods.filter(p => p.toMin > p.fromMin);

  const paidMinutes = Math.max(
    0,
    periods.reduce((sum, p) => sum + (p.toMin - p.fromMin), 0)
  );
  const paidHours = +(paidMinutes / 60).toFixed(2);

  // pay
  let basePay = 0, bonusPay = 0;
  for (const p of periods) {
    const h = (p.toMin - p.fromMin) / 60;
    basePay += h * p.baseRate;
    bonusPay += h * p.bonusRate;
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
    breakAudit: {
      ...afterPolicy.audit,
      deductedHours: +(afterPolicy.audit.deductedHours + manualPauseHours).toFixed(2),
      notes: [...(afterPolicy.audit.notes || []), manualPauseHours > 0 ? "Manual pause applied at end of shift" : undefined].filter(Boolean) as string[],
    }
  };
}
