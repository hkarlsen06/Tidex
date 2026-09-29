import { SupplementRule, WagePeriod } from "./types.ts";

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
    return (baseRate * rule.percent) / 100;
  }
  return 0;
}

export function buildWagePeriods(
  startHHMM: string,
  endHHMM: string,
  weekday: number,
  baseRate: number,
  rules: SupplementRule[],
): WagePeriod[] {
  const start = toMin(startHHMM);
  let end = toMin(endHHMM);
  if (start == null || end == null) return [];
  if (end <= start) end += 24 * 60;

  const windows: { from: number; to: number; rate: number }[] = [];
  for (const rule of rules) {
    const from = toMin(rule.from);
    const to = toMin(rule.to);
    if (from == null || to == null || from === to) continue;
    // Weekdays identify the rule's start day, including overnight carry from yesterday.
    for (const dayOffset of [-1, 0, 1]) {
      const ruleWeekday = ((weekday - 1 + dayOffset + 7) % 7) + 1;
      if (!rule.days.includes(ruleWeekday)) continue;
      const windowFrom = from + dayOffset * 24 * 60;
      const windowTo = to + dayOffset * 24 * 60 + (to < from ? 24 * 60 : 0);
      if (windowTo <= start || windowFrom >= end) continue;
      windows.push({ from: windowFrom, to: windowTo, rate: resolveSupplementRate(rule, baseRate) });
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
    let supplementRate = 0;
    for (const window of windows) {
      if (fromMin >= window.from && toMin <= window.to) {
        supplementRate = Math.max(supplementRate, window.rate);
      }
    }
    periods.push({ fromMin, toMin, baseRate, supplementRate, totalRate: baseRate + supplementRate });
  }
  return periods;
}
