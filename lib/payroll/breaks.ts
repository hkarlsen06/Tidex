import { BreakAudit, BreakMethod, BreakPolicy, WagePeriod } from "./types";

export function applyBreakDeduction(
  periods: WagePeriod[],
  policy: BreakPolicy,
  method: BreakMethod,
  thresholdHours: number,
  deductionHours: number
): { periods: WagePeriod[]; audit: BreakAudit; paidHours: number } {
  const totalMinutes = periods.reduce((s, p) => s + (p.toMin - p.fromMin), 0);
  const totalHours = totalMinutes / 60;

  let toDeduct = 0;
  if (policy === "fixed_0_5_over_5_5h" && totalHours > thresholdHours) {
    toDeduct = Math.max(toDeduct, deductionHours || 0.5);
  }
  // "none" keeps toDeduct at 0. Other named policies can map to same logic for now.

  let paidMinutes = totalMinutes - Math.round(toDeduct * 60);
  if (paidMinutes < 0) paidMinutes = 0;

  let adjusted = periods.map(p => ({ ...p }));
  const notes: string[] = [];

  if (toDeduct > 0 && method !== "none") {
    let remaining = Math.round(toDeduct * 60);

    if (method === "end_of_shift") {
      // subtract from the tail
      for (let i = adjusted.length - 1; i >= 0 && remaining > 0; i--) {
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const cut = Math.min(span, remaining);
        adjusted[i].toMin -= cut;
        remaining -= cut;
      }
      notes.push("Deducted at end of shift");
    } else if (method === "proportional") {
      const proportionalCuts = adjusted.map(p => {
        const span = p.toMin - p.fromMin;
        return Math.floor((span / totalMinutes) * Math.round(toDeduct * 60));
      });
      // fix rounding by consuming remainder from the end
      let used = proportionalCuts.reduce((s, v) => s + v, 0);
      let rem = Math.round(toDeduct * 60) - used;
      for (let i = adjusted.length - 1; i >= 0 && rem > 0; i--) {
        proportionalCuts[i] += 1; rem -= 1;
      }
      for (let i = 0; i < adjusted.length; i++) {
        adjusted[i].toMin -= Math.min(adjusted[i].toMin - adjusted[i].fromMin, proportionalCuts[i]);
      }
      notes.push("Deducted proportionally across periods");
    } else if (method === "base_only") {
      // prefer periods with lowest bonus
      const order = adjusted
        .map((p, idx) => ({ idx, bonus: p.bonusRate }))
        .sort((a, b) => a.bonus - b.bonus)
        .map(o => o.idx);
      for (const i of order) {
        if (remaining <= 0) break;
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const cut = Math.min(span, remaining);
        adjusted[i].toMin -= cut;
        remaining -= cut;
      }
      notes.push("Deducted from base/lowest bonus periods first");
    }
    // trim empty periods
    adjusted = adjusted.filter(p => p.toMin > p.fromMin);
  }

  const audit: BreakAudit = {
    method,
    policy,
    thresholdHours,
    deductedHours: toDeduct,
    notes,
  };
  return { periods: adjusted, audit, paidHours: paidMinutes / 60 };
}
