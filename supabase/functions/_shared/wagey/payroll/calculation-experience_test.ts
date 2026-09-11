import { assertAlmostEquals, assertEquals } from "jsr:@std/assert";

import { applyBreakDeduction } from "./breaks.ts";
import { applyWeeklyOvertime, computeShift } from "./calc.ts";
import { buildWagePeriods } from "./periods.ts";
import type { ShiftRow, SupplementRule, WageSnapshot } from "./types.ts";

const snapshot: WageSnapshot = {
  id: "snapshot", user_id: "user", from_date: null,
  hourly_wage: 200, wage_level: null, tariff_type_id: null,
  supplements: { rules: [] }, tax_enabled: false, tax_percentage: 0,
  break_enabled: false, break_method: "none",
  break_threshold_hours: 5.5, break_deduction_minutes: 30,
};

function compute(
  date: string,
  start: string,
  end: string,
  rules: SupplementRule[] = [],
  overrides: Partial<WageSnapshot> = {},
  shiftOverrides: Partial<ShiftRow> = {},
) {
  return computeShift({
    id: "shift", user_id: "user", shift_date: date,
    start_time: start, end_time: end, ...shiftOverrides,
  }, {}, [], { ...snapshot, supplements: { rules }, ...overrides });
}

Deno.test("Saturday night switches to Sunday's supplement at midnight", () => {
  const result = compute("2026-02-07", "22:00", "02:00", [
    { days: [6], from: "18:00", to: "24:00", rate: 50 },
    { days: [7], from: "00:00", to: "24:00", rate: 100 },
  ]);
  assertEquals(result.basePay, 800);
  assertEquals(result.supplementPay, 300);
  assertEquals(result.gross, 1100);
});

Deno.test("Sunday supplement stops when a shift continues into Monday", () => {
  const result = compute("2026-02-08", "22:00", "02:00", [
    { days: [7], from: "00:00", to: "24:00", rate: 100 },
  ]);
  assertEquals(result.supplementPay, 200);
});

Deno.test("early shift receives the previous day's overnight rule", () => {
  const result = compute("2026-02-08", "01:00", "03:00", [
    { days: [6], from: "22:00", to: "06:00", rate: 60 },
  ]);
  assertEquals(result.supplementPay, 120);
});

Deno.test("overlapping overnight rules pay only the highest applicable rate", () => {
  const result = compute("2026-02-07", "23:00", "03:00", [
    { days: [6], from: "22:00", to: "06:00", rate: 60 },
    { days: [7], from: "00:00", to: "24:00", percent: 50 },
  ]);
  assertEquals(result.supplementPay, 360);
});

Deno.test("shift-specific supplements still apply after midnight", () => {
  const result = compute("2026-02-07", "22:00", "02:00", [], {}, {
    custom_supplements: { rules: [{ from: "00:00", to: "02:00", rate: 80 }] },
  });
  assertEquals(result.supplementPay, 160);
});

Deno.test("one minute of work is paid from exact minutes", () => {
  const result = compute("2026-02-02", "08:00", "08:01");
  assertEquals(result.basePay, 3.33);
  assertAlmostEquals(result.paidHours * 60, 1);
  assertAlmostEquals(result.durationHours * 60, 1);
});

Deno.test("splitting periods cannot change pay for an unchanged rate", () => {
  const unsplit = compute("2026-02-02", "08:00", "09:00", [
    { days: [1], from: "08:00", to: "09:00", rate: 20 },
  ]);
  const split = compute("2026-02-02", "08:00", "09:00", [
    { days: [1], from: "08:00", to: "08:01", rate: 20 },
    { days: [1], from: "08:01", to: "08:02", rate: 20 },
    { days: [1], from: "08:02", to: "09:00", rate: 20 },
  ]);
  assertEquals(split.gross, unsplit.gross);
  assertEquals(split.basePay, 200);
  assertEquals(split.supplementPay, 20);
});

Deno.test("tariff half-cent rounding is independent of period splits", () => {
  for (const [rate, minutes, split, expected] of [
    [184.54, 45, 7, 138.41], [185.38, 15, 4, 46.35],
    [187.46, 15, 4, 46.87], [193.05, 10, 2, 32.18],
    [210.81, 30, 9, 105.41], [256.14, 45, 3, 192.11],
    [193.049999, 10, 2, 32.17],
  ]) {
    const end = `08:${String(minutes).padStart(2, "0")}` as SupplementRule["to"];
    const cut = `08:${String(split).padStart(2, "0")}` as SupplementRule["from"];
    const unsplit = compute("2026-02-02", "08:00", end, [], { hourly_wage: rate });
    const splitShift = compute("2026-02-02", "08:00", end, [
      { days: [1], from: "08:00", to: cut, rate },
      { days: [1], from: cut, to: end, rate },
    ], { hourly_wage: rate });
    assertEquals(unsplit.basePay, expected);
    assertEquals(splitShift.basePay, expected);
    assertEquals(splitShift.supplementPay, expected);
  }
});

Deno.test("overtime recomputation preserves exact minute pay", () => {
  const shift: ShiftRow = {
    id: "shift", user_id: "user", shift_date: "2026-02-02",
    start_time: "08:00", end_time: "08:01",
  };
  const [result] = applyWeeklyOvertime([{
    ...shift, computed: computeShift(shift, {}, [], snapshot),
    tax_enabled: false, tax_percentage: 0,
  }], {
    snapshotForShift: () => snapshot,
    effectiveJobIdForShift: () => null,
  });
  assertEquals(result.computed.basePay, 3.33);
});

Deno.test("no-break method reports no deducted time or automatic deduction", () => {
  const result = compute("2026-02-02", "08:00", "16:00", [], {
    break_enabled: true, break_method: "none",
  });
  assertEquals(result.paidHours, 8);
  assertEquals(result.breakAudit.deductedHours, 0);
  assertEquals(result.breakAudit.source, "none");
});

Deno.test("short shifts do not report an automatic break", () => {
  const result = compute("2026-02-02", "08:00", "10:00", [], {
    break_enabled: true, break_method: "proportional",
  });
  assertEquals(result.breakAudit.source, "none");
});

Deno.test("break deductions are capped to actual shift duration", () => {
  const periods = buildWagePeriods("08:00", "08:15", 1, 200, []);
  for (const method of ["proportional", "end_of_shift", "base_only"] as const) {
    const result = applyBreakDeduction(periods, method, 0, 0.5);
    assertAlmostEquals(result.audit.deductedHours, 0.25);
    assertEquals(result.periods, []);
  }
});

Deno.test("malformed persisted time does not produce invalid payroll", () => {
  const result = compute("2026-02-02", "not-a-time", "10:00");
  assertEquals(result.gross, 0);
  assertEquals(result.durationHours, 0);
});
