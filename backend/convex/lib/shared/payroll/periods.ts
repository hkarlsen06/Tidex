import { SupplementRule, WagePeriod } from "./types";

function toMin(hhmm: string): number | null {
  if (!/^\d{1,2}:\d{2}$/.test(hhmm)) return null;
  const [hours, minutes] = hhmm.split(":").map(Number);
  if (hours > 24 || minutes >= 60 || (hours === 24 && minutes !== 0)) return null;
  return hours * 60 + minutes;
}

function resolveSupplementRate(rule: SupplementRule, baseRate: number): number {
  if (rule.rate != null && Number.isFinite(rule.rate) && rule.rate >= 0) {
    return rule.rate;
  }
  if (rule.percent != null && Number.isFinite(rule.percent) && rule.percent >= 0) {
    const basis = rule.percentageBaseRate ?? baseRate;
    const minimum = rule.minimumRate ?? 0;
    if (!Number.isFinite(basis) || basis < 0 || !Number.isFinite(minimum) || minimum < 0) return 0;
    return Math.max(minimum, (basis * rule.percent) / 100);
  }
  return 0;
}

export function buildWagePeriods(
  startHHMM: string,
  endHHMM: string,
  weekday: number,
  baseRate: number,
  rules: SupplementRule[],
  shiftDate?: string,
): WagePeriod[] {
  const start = toMin(startHHMM);
  let end = toMin(endHHMM);
  if (start == null || end == null) return [];
  if (end <= start) end += 24 * 60;

  const windows: { from: number; to: number; rate: number; group: string }[] = [];
  for (const rule of rules) {
    if (rule.shiftStartBefore != null) {
      const before = toMin(rule.shiftStartBefore);
      if (before == null || start >= before) continue;
    }
    if (rule.shiftStartDates && (!shiftDate || !rule.shiftStartDates.includes(shiftDate))) continue;
    if (shiftDate && rule.excludedShiftStartDates?.includes(shiftDate)) continue;
    const from = toMin(rule.from);
    const to = toMin(rule.to);
    if (from == null || to == null || from === to) continue;
    // Weekdays identify the rule's start day, including overnight carry from yesterday.
    for (const dayOffset of [-1, 0, 1]) {
      const ruleWeekday = ((weekday - 1 + dayOffset + 7) % 7) + 1;
      if (!rule.days.includes(ruleWeekday)) continue;
      const ruleDate = shiftDate ? new Date(`${shiftDate}T00:00:00Z`) : null;
      if (ruleDate) ruleDate.setUTCDate(ruleDate.getUTCDate() + dayOffset);
      const isoDate = ruleDate && Number.isFinite(ruleDate.getTime()) ? ruleDate.toISOString().slice(0, 10) : null;
      if (rule.dates && (!isoDate || !rule.dates.includes(isoDate))) continue;
      if (isoDate && rule.excludedDates?.includes(isoDate)) continue;
      const windowFrom = from + dayOffset * 24 * 60;
      const windowTo = to + dayOffset * 24 * 60 + (to < from ? 24 * 60 : 0);
      if (windowTo <= start || windowFrom >= end) continue;
      windows.push({ from: windowFrom, to: windowTo, rate: resolveSupplementRate(rule, baseRate), group: rule.stackingGroup ?? "" });
    }
  }

  const points = new Set<number>([start, end]);
  for (const window of windows) {
    points.add(Math.max(start, window.from));
    points.add(Math.min(end, window.to));
  }
  const sorted = Array.from(points).sort((a, b) => a - b);
  const periods: WagePeriod[] = [];
  for (let index = 0; index < sorted.length - 1; index++) {
    const fromMin = sorted[index], toMin = sorted[index + 1];
    const groups = new Map<string, number>();
    for (const window of windows) {
      if (fromMin >= window.from && toMin <= window.to) {
        groups.set(window.group, Math.max(groups.get(window.group) ?? 0, window.rate));
      }
    }
    const supplementRate = [...groups.values()].reduce((sum, rate) => sum + rate, 0);
    periods.push({ fromMin, toMin, baseRate, supplementRate, totalRate: baseRate + supplementRate });
  }
  return periods;
}
