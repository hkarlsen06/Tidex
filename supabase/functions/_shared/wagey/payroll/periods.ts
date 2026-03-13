import { SupplementRule, WagePeriod } from "./types.ts";

const toMin = (hhmm: string) => {
  const [h, m] = hhmm.split(":").map(Number);
  // Normalize 24:00 to 1440 minutes (end of day, which equals 00:00 next day)
  // The cross-midnight logic will handle this correctly
  return h * 60 + m;
};

function resolveSupplementRate(rule: SupplementRule, baseRate: number): number {
  // If 'rate' is specified, use it as fixed NOK per hour
  if (rule.rate != null && !isNaN(rule.rate)) {
    return rule.rate;
  }
  // If 'percent' is specified, calculate as percentage of base rate
  if (rule.percent != null && !isNaN(rule.percent)) {
    return (baseRate * rule.percent) / 100;
  }
  return 0;
}

export function buildWagePeriods(
  startHHMM: string,
  endHHMM: string,
  weekday: number,                  // 1-7 Mon..Sun
  baseRate: number,
  rules: SupplementRule[]
): WagePeriod[] {
  // normalize cross-midnight by allowing end < start and adding 24h
  let start = toMin(startHHMM);
  let end = toMin(endHHMM);
  if (end <= start) end += 24 * 60;

  // Collect rule boundaries
  const points = new Set<number>([start, end]);
  for (const r of rules) {
    if (!r.days.includes(weekday)) continue;
    const rf = toMin(r.from);
    let rt = toMin(r.to);
    // Handle cross-midnight rules: if to < from, add 24h to rt
    if (rt < rf) {
      rt += 24 * 60;
    }
    // rt is inclusive, no need to add 1 since supplement matching uses inclusive logic
    // consider both same-day and next-day windows
    for (const base of [0, 24 * 60]) {
      const a = rf + base, b = rt + base;
      if (b < start || a > end) continue;
      if (a > start && a < end) points.add(a);
      if (b > start && b < end) points.add(b);
    }
  }

  const sorted = Array.from(points).sort((a, b) => a - b);
  const out: WagePeriod[] = [];

  for (let i = 0; i < sorted.length - 1; i++) {
    const a = sorted[i], b = sorted[i + 1];
    // find highest matching supplement in [a,b)
    let supplement = 0;
    for (const r of rules) {
      if (!r.days.includes(weekday)) continue;
      for (const base of [0, 24 * 60]) {
        const rf = toMin(r.from) + base;
        let rt = toMin(r.to) + base;
        // Handle cross-midnight rules: if to < from, add 24h to rt
        if (toMin(r.to) < toMin(r.from)) {
          rt += 24 * 60;
        }
        // Check if period [a,b) is fully within rule [rf, rt] (rt is inclusive)
        // Period [a,b) means from minute a (inclusive) to minute b (exclusive)
        // So we need: a >= rf (period starts at or after rule starts)
        //         and b-1 <= rt (period ends at or before rule ends, since b is exclusive)
        if (a >= rf && b - 1 <= rt) {
          const supplementValue = resolveSupplementRate(r, baseRate);
          supplement = Math.max(supplement, supplementValue);
        }
      }
    }
    out.push({ fromMin: a, toMin: b, baseRate, supplementRate: supplement, totalRate: baseRate + supplement });
  }
  return out;
}
