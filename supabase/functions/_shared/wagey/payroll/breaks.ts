import { BreakAudit, BreakMethod, WagePeriod } from "./types.ts";

export function applyBreakDeduction(
  periods: WagePeriod[],
  method: BreakMethod,
  thresholdHours: number,
  deductionHours: number
): { periods: WagePeriod[]; audit: BreakAudit } {
  const totalMinutes = periods.reduce((s, p) => s + (p.toMin - p.fromMin), 0);
  const totalHours = totalMinutes / 60;

  // Only deduct if shift exceeds threshold
  let toDeduct = totalHours > thresholdHours ? deductionHours : 0;

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
      // Deduct exact proportional fractions (not rounded to minutes)
      for (let i = 0; i < adjusted.length; i++) {
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const proportion = span / totalMinutes;
        const cutMinutes = proportion * toDeduct * 60;
        adjusted[i].toMin -= cutMinutes;
      }
      notes.push("Deducted proportionally across periods");
    } else if (method === "base_only") {
      // prefer periods with lowest supplement
      const order = adjusted
        .map((p, idx) => ({ idx, supplement: p.supplementRate }))
        .sort((a, b) => a.supplement - b.supplement)
        .map(o => o.idx);
      for (const i of order) {
        if (remaining <= 0) break;
        const span = adjusted[i].toMin - adjusted[i].fromMin;
        const cut = Math.min(span, remaining);
        adjusted[i].toMin -= cut;
        remaining -= cut;
      }
      notes.push("Deducted from base/lowest supplement periods first");
    }
    // trim empty periods
    adjusted = adjusted.filter(p => p.toMin > p.fromMin);
  }

  const audit: BreakAudit = {
    method,
    thresholdHours,
    deductedHours: toDeduct,
    source: "automatic_break",
    notes,
  };
  return { periods: adjusted, audit };
}
