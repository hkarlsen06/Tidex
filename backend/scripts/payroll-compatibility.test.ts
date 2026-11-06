import { expect, test } from "bun:test";
import {
  needsReviewedPayroll,
  requirePayrollRevision,
} from "../convex/lib/payrollCompatibility";

test("older clients keep access to legacy wage snapshots", () => {
  const legacy = {
    hourly_wage: 195.04,
    supplements: {
      rules: [{ days: [1], from: "18:00", to: "21:00", rate: 22 }],
    },
    overtime: { retainSupplements: false },
  };
  expect(needsReviewedPayroll(legacy)).toBe(false);
  expect(() => requirePayrollRevision(undefined, legacy)).not.toThrow();
});

test("older clients cannot receive richer pay rules through sync or sharing", () => {
  for (const rich of [
    { supplements: { rules: [{ dates: ["2026-12-25"], rate: 100 }] } },
    { custom_supplements: { rules: [{ stackingGroup: "night", rate: 28 }] } },
    { overtime: { retainSupplements: true } },
    {
      overtime: {
        retainedSupplements: [
          { days: [1], from: "00:00", to: "24:00", rate: 20 },
        ],
      },
    },
    { overtime: { weeklyThresholdHours: 37.5, baseRate: 247.29 } },
    { overtime: { premiumBaseMultiplier: 1950 / 1850 } },
    { rules: [{ shiftStartDates: [], percent: 100 }] },
    { rules: [{ excludedShiftStartDates: ["2026-12-24"], rate: 58.04 }] },
  ]) {
    expect(() =>
      requirePayrollRevision(undefined, { snapshots: [rich] }),
    ).toThrow("payroll_update_required");
    expect(() =>
      requirePayrollRevision("2026-11", { snapshots: [rich] }),
    ).not.toThrow();
  }
});
