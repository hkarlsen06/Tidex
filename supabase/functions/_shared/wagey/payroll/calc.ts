import { applyBreakDeduction } from "./breaks.ts";
import {
  applyCustomPauseWindowClipping,
  normalizeCustomPauseWindows,
} from "./pause-windows.ts";
import { buildWagePeriods } from "./periods.ts";
import { isNorwegianPublicHoliday } from "./norwegian-holidays.ts";
import {
  BreakMethod,
  CustomSupplementsData,
  Job,
  OvertimeConfig,
  OvertimeRule,
  ShiftComputed,
  ShiftRow,
  ShiftWithComputations,
  SupplementRule,
  UserSettings,
  WagePeriod,
  WageSnapshot,
} from "./types.ts";

const WEEKDAYS = [7, 1, 2, 3, 4, 5, 6]; // JS getDay(): 0=Sun → 7, then 1..6 Mon..Sat
export const PRESET_WAGE_RATES: Record<string, number> = {
  "-1": 129.91,
  "-2": 132.90,
  "1": 184.54,
  "2": 185.38,
  "3": 187.46,
  "4": 193.05,
  "5": 210.81,
  "6": 256.14,
};

const defaultBreakSettings = {
  break_enabled: true,
  break_method: "proportional" as BreakMethod,
  break_threshold_hours: 5.5,
  break_deduction_minutes: 30,
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
  if (snapshot?.hourly_wage && Number.isFinite(snapshot.hourly_wage) && snapshot.hourly_wage > 0) {
    return snapshot.hourly_wage;
  }

  // Priority 2: Backward compatibility - old per-shift snapshot
  if (s.hourly_wage_snapshot && Number.isFinite(s.hourly_wage_snapshot) && s.hourly_wage_snapshot > 0) {
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
 * @param predefinedRules - Rules from snapshot or preset
 * @param customSupplements - Shift-specific custom supplements
 * @returns Final supplement rules to use
 */
function resolveSupplementRules(
  predefinedRules: SupplementRule[],
  customSupplements: CustomSupplementsData | null | undefined,
): SupplementRule[] {
  if (!customSupplements || !customSupplements.rules) {
    return predefinedRules;
  }

  // Empty rules array means "explicitly no supplements" for this shift
  if (customSupplements.rules.length === 0) {
    return [];
  }

  // Custom supplements completely replace predefined rules
  // Convert custom supplement rules to full SupplementRule format (add days field)
  return customSupplements.rules.map((rule) => ({
    ...rule,
    days: [1, 2, 3, 4, 5, 6, 7], // Shift-specific clock windows also apply after midnight.
  }));
}

// Precision constants for payroll calculations
const CURRENCY_PRECISION = 100; // 2 decimal places (cents)

/**
 * Compute payroll for a single shift
 *
 * @param shift - The shift data
 * @param _settings - User's current settings (deprecated, kept for compatibility)
 * @param presetRules - Preset supplement rules (fallback if no snapshot)
 * @param snapshot - Wage snapshot containing wage, supplement, tax, and break settings
 * @returns Computed payroll data including gross pay, hours, and breakdown
 *
 * NOTE: Break deduction settings are now read from the snapshot, not UserSettings.
 * The settings parameter is kept for backward compatibility but is no longer used.
 */
export function computeShift(
  shift: ShiftRow,
  _settings: UserSettings,
  presetRules: SupplementRule[],
  snapshot: WageSnapshot | null = null,
  _job: Job | null = null,
): ShiftComputed {
  const s = { ...shift };
  const st = s.start_time;
  const et = s.end_time;
  const normalizedPauseWindows = normalizeCustomPauseWindows(
    s.custom_pause_windows,
  );

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
  const rules = resolveSupplementRules(
    predefinedRules,
    s.custom_supplements,
  );

  let periods: WagePeriod[] = buildWagePeriods(
    st,
    et,
    weekday,
    baseRate,
    rules,
  );

  // duration
  const totalMinutes = periods.reduce(
    (sum, p) => sum + (p.toMin - p.fromMin),
    0,
  );
  const durationHours = totalMinutes / 60;

  // Store original periods before break deduction (for display purposes)
  const originalWagePeriods = periods.map((p) => ({ ...p }));

  // Resolve break settings from snapshot (with defaults for backward compatibility)
  const breakEnabled = snapshot?.break_enabled ??
    defaultBreakSettings.break_enabled;
  const method = snapshot?.break_method ?? defaultBreakSettings.break_method;
  const threshold = snapshot?.break_threshold_hours ??
    defaultBreakSettings.break_threshold_hours;
  const breakMinutes = breakEnabled
    ? (snapshot?.break_deduction_minutes ??
      defaultBreakSettings.break_deduction_minutes)
    : 0;
  const breakHours = breakMinutes / 60;

  // Apply automatic break deduction
  let breakAudit;
  if (normalizedPauseWindows) {
    const afterPause = applyCustomPauseWindowClipping(
      periods,
      normalizedPauseWindows,
      st,
      et,
    );
    periods = afterPause.periods;
    breakAudit = {
      method: "none" as BreakMethod,
      thresholdHours: 0,
      deductedHours: afterPause.deductedHours,
      source: "custom_pause_windows" as const,
      appliedPauseWindows: afterPause.appliedPauseWindows,
      notes: afterPause.appliedPauseWindows?.length
        ? ["Deducted using custom pause windows"]
        : [],
    };
  } else {
    const afterBreak = applyBreakDeduction(
      periods,
      method,
      threshold,
      breakHours,
    );
    periods = afterBreak.periods;
    breakAudit = afterBreak.audit;
  }

  const paidMinutes = periods.reduce(
    (sum, p) => sum + (p.toMin - p.fromMin),
    0,
  );
  const paidHours = paidMinutes / 60;

  // pay
  const { basePay, supplementPay, gross } = payTotals(periods);

  return {
    id: s.id,
    durationHours,
    paidHours,
    basePay,
    supplementPay,
    gross,
    wagePeriods: periods,
    originalWagePeriods,
    breakAudit,
    overtimeApplied: false,
    overtimeMinutes: 0,
  };
}

type WeeklyOvertimeOptions = {
  snapshotForShift: (shift: ShiftWithComputations) => WageSnapshot | null;
  effectiveJobIdForShift: (shift: ShiftWithComputations) => string | null;
};

type OvertimeSegment = {
  shift: ShiftWithComputations;
  period: WagePeriod;
  absoluteStart: Date;
  absoluteEnd: Date;
  shiftDayStart: Date;
  config: OvertimeConfig | null;
};

type OvertimePiece = {
  shiftId: string;
  start: Date;
  period: WagePeriod;
  overtimeMinutes: number;
};

export function applyWeeklyOvertime(
  shifts: ShiftWithComputations[],
  options: WeeklyOvertimeOptions,
): ShiftWithComputations[] {
  if (!shifts.length) return shifts;

  const grouped = new Map<string, OvertimeSegment[]>();
  const fallbackPieces = new Map<string, OvertimePiece[]>();

  for (const shift of shifts) {
    const snapshot = options.snapshotForShift(shift);
    const config = runtimeOvertimeConfig(snapshot?.overtime ?? null);
    const shiftDayStart = parseISODateUTC(shift.shift_date);
    if (!shiftDayStart) continue;

    for (const period of shift.computed.wagePeriods) {
      const absoluteStart = addMinutes(shiftDayStart, period.fromMin);
      const absoluteEnd = addMinutes(shiftDayStart, period.toMin);
      if (absoluteEnd <= absoluteStart) continue;

      for (
        const [partStart, partEnd] of splitByISOWeek(absoluteStart, absoluteEnd)
      ) {
        const partPeriod = makePeriod(
          minutesBetween(shiftDayStart, partStart),
          minutesBetween(shiftDayStart, partEnd),
          period.baseRate,
          period.supplementRate,
        );
        const groupKey = [
          options.effectiveJobIdForShift(shift) ?? "__nil__",
          formatISODate(isoWeekStart(partStart)),
        ].join("|");
        const segment: OvertimeSegment = {
          shift,
          period: partPeriod,
          absoluteStart: partStart,
          absoluteEnd: partEnd,
          shiftDayStart,
          config,
        };
        grouped.set(groupKey, [...(grouped.get(groupKey) ?? []), segment]);
        pushPiece(fallbackPieces, {
          shiftId: shift.id,
          start: partStart,
          period: partPeriod,
          overtimeMinutes: 0,
        });
      }
    }
  }

  const pieces = new Map<string, OvertimePiece[]>();

  for (const segments of grouped.values()) {
    let cumulativeMinutes = 0;
    const sorted = [...segments].sort((a, b) => {
      const dateDiff = a.absoluteStart.getTime() - b.absoluteStart.getTime();
      if (dateDiff !== 0) return dateDiff;
      return a.shift.id.localeCompare(b.shift.id);
    });

    for (const segment of sorted) {
      for (const piece of applyOvertimeToSegment(segment, cumulativeMinutes)) {
        pushPiece(pieces, piece);
      }
      cumulativeMinutes += segment.period.toMin - segment.period.fromMin;
    }
  }

  return shifts.map((shift) => {
    const shiftPieces = pieces.get(shift.id) ?? fallbackPieces.get(shift.id) ??
      [];
    if (!shiftPieces.length) return shift;

    const sortedPieces = [...shiftPieces].sort((a, b) => {
      const dateDiff = a.start.getTime() - b.start.getTime();
      if (dateDiff !== 0) return dateDiff;
      return a.period.fromMin - b.period.fromMin;
    });
    const periods = mergeAdjacentPeriods(
      sortedPieces.map((piece) => piece.period),
    );
    const overtimeMinutes = sortedPieces.reduce(
      (sum, piece) => sum + piece.overtimeMinutes,
      0,
    );

    return {
      ...shift,
      computed: recomputeWithPeriods(shift.computed, periods, overtimeMinutes),
    };
  });
}

function applyOvertimeToSegment(
  segment: OvertimeSegment,
  cumulativeMinutes: number,
): OvertimePiece[] {
  if (!segment.config) {
    return [{
      shiftId: segment.shift.id,
      start: segment.absoluteStart,
      period: segment.period,
      overtimeMinutes: 0,
    }];
  }

  const thresholdMinutes = segment.config.weeklyThresholdHours * 60;
  const pieces: OvertimePiece[] = [];
  let cursor = segment.absoluteStart;
  let cursorCumulative = cumulativeMinutes;

  while (cursor < segment.absoluteEnd) {
    const next = nextOvertimeBoundary(
      cursor,
      segment.absoluteEnd,
      segment.config,
      cursorCumulative,
      thresholdMinutes,
    );
    const durationMinutes = minutesBetween(cursor, next);
    if (durationMinutes <= 0) break;

    const isOvertime = cursorCumulative >= thresholdMinutes;
    const percent = isOvertime ? overtimePercent(segment.config, cursor) : null;
    const supplementRate = percent == null
      ? segment.period.supplementRate
      : segment.period.baseRate * percent / 100;

    pieces.push({
      shiftId: segment.shift.id,
      start: cursor,
      period: makePeriod(
        minutesBetween(segment.shiftDayStart, cursor),
        minutesBetween(segment.shiftDayStart, next),
        segment.period.baseRate,
        supplementRate,
        percent != null,
      ),
      overtimeMinutes: percent == null ? 0 : durationMinutes,
    });

    cursorCumulative += durationMinutes;
    cursor = next;
  }

  return pieces;
}

function nextOvertimeBoundary(
  date: Date,
  segmentEnd: Date,
  config: OvertimeConfig,
  cumulativeMinutes: number,
  thresholdMinutes: number,
): Date {
  let boundary = segmentEnd;
  const dayStart = startOfUTCDay(date);
  const nextDay = addDays(dayStart, 1);
  if (nextDay > date) boundary = minDate(boundary, nextDay);

  if (cumulativeMinutes < thresholdMinutes) {
    const thresholdDate = addMinutes(
      date,
      thresholdMinutes - cumulativeMinutes,
    );
    if (thresholdDate > date) boundary = minDate(boundary, thresholdDate);
  }

  const minuteOfDay = minutesBetween(dayStart, date);
  for (const rule of config.rules) {
    if (!overtimeRuleCanMatch(rule, date)) continue;
    const from = timeToMinutes(rule.from);
    const to = timeToMinutes(rule.to);
    if (from == null || to == null) continue;
    for (const value of [from, to]) {
      if (value <= minuteOfDay) continue;
      const candidate = addMinutes(dayStart, value);
      if (candidate > date) boundary = minDate(boundary, candidate);
    }
  }

  return boundary;
}

function recomputeWithPeriods(
  computed: ShiftComputed,
  periods: WagePeriod[],
  overtimeMinutes: number,
): ShiftComputed {
  return {
    ...computed,
    ...payTotals(periods),
    wagePeriods: periods,
    overtimeApplied: overtimeMinutes > 0,
    overtimeMinutes: +overtimeMinutes.toFixed(2),
  };
}

// Round once per pay component, never round hours or intermediate period amounts.
function payTotals(periods: WagePeriod[]) {
  let basePay = 0;
  let supplementPay = 0;
  for (const period of periods) {
    const hours = Math.max(0, period.toMin - period.fromMin) / 60;
    basePay += hours * period.baseRate;
    supplementPay += hours * period.supplementRate;
  }
  basePay = Math.round(basePay * CURRENCY_PRECISION) / CURRENCY_PRECISION;
  supplementPay = Math.round(supplementPay * CURRENCY_PRECISION) / CURRENCY_PRECISION;
  return {
    basePay,
    supplementPay,
    gross: Math.round((basePay + supplementPay) * CURRENCY_PRECISION) / CURRENCY_PRECISION,
  };
}

function runtimeOvertimeConfig(
  config: OvertimeConfig | null,
): OvertimeConfig | null {
  if (!config?.enabled) return null;
  if (
    !Number.isFinite(config.weeklyThresholdHours) ||
    config.weeklyThresholdHours <= 0
  ) {
    return null;
  }
  if (!config.rules.length || !config.rules.every(isValidOvertimeRule)) {
    return null;
  }
  if (!rulesCoverFullDay(config.rules, false)) return null;
  if (!rulesCoverFullDay(config.rules, true)) return null;
  return config;
}

function isValidOvertimeRule(rule: OvertimeRule): boolean {
  const from = timeToMinutes(rule.from);
  const to = timeToMinutes(rule.to);
  return rule.days.length > 0 &&
    rule.days.every((day) => Number.isInteger(day) && day >= 1 && day <= 7) &&
    Number.isFinite(rule.percent) &&
    rule.percent > 0 &&
    from != null &&
    to != null &&
    from < to &&
    to <= 24 * 60;
}

function rulesCoverFullDay(rules: OvertimeRule[], holiday: boolean): boolean {
  for (let day = 1; day <= 7; day++) {
    const intervals = rules
      .filter((rule) =>
        rule.days.includes(day) &&
        (holiday ? rule.appliesOnHolidays : !isHolidayOnlyRule(rule))
      )
      .map((rule) =>
        [timeToMinutes(rule.from), timeToMinutes(rule.to)] as const
      )
      .filter((interval): interval is readonly [number, number] =>
        interval[0] != null && interval[1] != null
      );
    if (!intervalsCoverFullDay(intervals)) return false;
  }
  return true;
}

function intervalsCoverFullDay(
  intervals: readonly (readonly [number, number])[],
): boolean {
  let coveredUntil = 0;
  for (const [from, to] of [...intervals].sort((a, b) => a[0] - b[0])) {
    if (from > coveredUntil) return false;
    coveredUntil = Math.max(coveredUntil, to);
    if (coveredUntil >= 24 * 60) return true;
  }
  return false;
}

function overtimePercent(config: OvertimeConfig, date: Date): number | null {
  const minute = minutesBetween(startOfUTCDay(date), date);
  const matches = config.rules
    .filter((rule) => overtimeRuleCanMatch(rule, date))
    .filter((rule) => {
      const from = timeToMinutes(rule.from);
      const to = timeToMinutes(rule.to);
      return from != null && to != null && minute >= from && minute < to;
    })
    .map((rule) => rule.percent);
  return matches.length ? Math.max(...matches) : null;
}

function overtimeRuleCanMatch(rule: OvertimeRule, date: Date): boolean {
  const weekday = WEEKDAYS[date.getUTCDay()];
  if (!rule.days.includes(weekday)) return false;
  if (isNorwegianPublicHoliday(date)) return rule.appliesOnHolidays;
  return !isHolidayOnlyRule(rule);
}

function isHolidayOnlyRule(rule: OvertimeRule): boolean {
  return rule.appliesOnHolidays && rule.days.length === 7 &&
    new Set(rule.days).size === 7;
}

function timeToMinutes(value: string): number | null {
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes)) return null;
  if (minutes < 0 || minutes >= 60 || hours < 0 || hours > 24) return null;
  if (hours === 24 && minutes !== 0) return null;
  return hours * 60 + minutes;
}

function splitByISOWeek(start: Date, end: Date): Array<[Date, Date]> {
  const result: Array<[Date, Date]> = [];
  let cursor = start;
  while (cursor < end) {
    const weekEnd = addDays(isoWeekStart(cursor), 7);
    const partEnd = minDate(end, weekEnd);
    result.push([cursor, partEnd]);
    cursor = partEnd;
  }
  return result;
}

function isoWeekStart(date: Date): Date {
  const start = startOfUTCDay(date);
  const day = start.getUTCDay();
  const mondayOffset = (day + 6) % 7;
  return addDays(start, -mondayOffset);
}

function parseISODateUTC(value: string): Date | null {
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function startOfUTCDay(date: Date): Date {
  return new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
}

function formatISODate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function addDays(date: Date, days: number): Date {
  return addMinutes(date, days * 24 * 60);
}

function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60_000);
}

function minutesBetween(start: Date, end: Date): number {
  return (end.getTime() - start.getTime()) / 60_000;
}

function minDate(a: Date, b: Date): Date {
  return a <= b ? a : b;
}

function makePeriod(
  fromMin: number,
  toMin: number,
  baseRate: number,
  supplementRate: number,
  isOvertime?: boolean,
): WagePeriod {
  return {
    fromMin,
    toMin,
    baseRate,
    supplementRate,
    totalRate: baseRate + supplementRate,
    ...(isOvertime == null ? {} : { isOvertime }),
  };
}

function mergeAdjacentPeriods(periods: WagePeriod[]): WagePeriod[] {
  const merged: WagePeriod[] = [];
  for (const period of periods) {
    if (period.toMin <= period.fromMin) continue;
    const last = merged.at(-1);
    if (
      last &&
      Math.abs(last.toMin - period.fromMin) < 0.0001 &&
      last.baseRate === period.baseRate &&
      last.supplementRate === period.supplementRate &&
      last.isOvertime === period.isOvertime
    ) {
      merged[merged.length - 1] = makePeriod(
        last.fromMin,
        period.toMin,
        last.baseRate,
        last.supplementRate,
        last.isOvertime,
      );
    } else {
      merged.push(period);
    }
  }
  return merged;
}

function pushPiece(
  map: Map<string, OvertimePiece[]>,
  piece: OvertimePiece,
): void {
  map.set(piece.shiftId, [...(map.get(piece.shiftId) ?? []), piece]);
}
