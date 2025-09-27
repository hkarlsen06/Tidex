import { BonusRule, WagePeriod } from "./types";

const toMin = (hhmm: string) => {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
};

export function buildWagePeriods(
  startHHMM: string,
  endHHMM: string,
  weekday: number,                  // 1-7 Mon..Sun
  baseRate: number,
  rules: BonusRule[]
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
    const rt = toMin(r.to) + 1; // inclusive to → make exclusive
    // consider both same-day and next-day windows
    for (const base of [0, 24 * 60]) {
      const a = rf + base, b = rt + base;
      if (b <= start || a >= end) continue;
      points.add(Math.max(a, start));
      points.add(Math.min(b, end));
    }
  }

  const sorted = Array.from(points).sort((a, b) => a - b);
  const out: WagePeriod[] = [];

  for (let i = 0; i < sorted.length - 1; i++) {
    const a = sorted[i], b = sorted[i + 1];
    // find highest matching bonus in [a,b)
    let bonus = 0;
    for (const r of rules) {
      if (!r.days.includes(weekday)) continue;
      for (const base of [0, 24 * 60]) {
        const rf = toMin(r.from) + base;
        const rt = toMin(r.to) + base + 1;
        if (a >= rf && b <= rt) bonus = Math.max(bonus, r.rate);
      }
    }
    out.push({ fromMin: a, toMin: b, baseRate, bonusRate: bonus, totalRate: baseRate + bonus });
  }
  return out;
}
