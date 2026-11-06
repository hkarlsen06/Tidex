import { describe, expect, test } from "bun:test";
import { buildWagePeriods } from "../convex/lib/shared/payroll/periods";
import { applyWeeklyOvertime, computeShift } from "../convex/lib/shared/payroll/calc";
import type { OvertimeConfig, ShiftRow, SupplementRule, WageSnapshot } from "../convex/lib/shared/payroll/types";

const weekdays = [1, 2, 3, 4, 5, 6, 7];
const overtime: OvertimeConfig = {
  enabled: true,
  weeklyThresholdHours: 1,
  rules: [
    { days: weekdays, from: "00:00", to: "24:00", percent: 50, appliesOnHolidays: false },
    { days: weekdays, from: "00:00", to: "24:00", percent: 50, appliesOnHolidays: true },
  ],
};

function snapshot(config: OvertimeConfig): WageSnapshot {
  return {
    id: "wage", user_id: "user", job_id: "job", from_date: null,
    hourly_wage: 200, wage_level: 1, tariff_type_id: "riksavtalen_hotel",
    supplements: { rules: [{ days: weekdays, from: "00:00", to: "24:00", rate: 20 }] },
    overtime: config, tax_enabled: false, tax_percentage: 0,
    break_enabled: false, break_method: "none", break_threshold_hours: 0, break_deduction_minutes: 0,
  };
}

function compute(config: OvertimeConfig) {
  const wage = snapshot(config);
  const shift: ShiftRow = {
    id: "shift", user_id: "user", job_id: "job", shift_date: "2026-02-02",
    start_time: "08:00", end_time: "10:00",
  };
  return applyWeeklyOvertime([{ ...shift, computed: computeShift(shift, {}, [], wage) }], {
    snapshotForShift: () => wage, effectiveJobIdForShift: () => "job",
  })[0].computed;
}

describe("reviewed tariff rules preserve legacy payroll", () => {
  test("old snapshots keep replacing UB during overtime", () => {
    expect(compute(overtime).gross).toBe(520);
  });

  test("Riksavtalen retains UB without applying overtime percentage to UB", () => {
    expect(compute({ ...overtime, retainSupplements: true }).gross).toBe(540);
  });

  test("premium divisor changes only the overtime supplement basis", () => {
    expect(compute({ ...overtime, premiumBaseMultiplier: 1950 / 1850 }).gross).toBe(525.41);
  });

  test("an invalid premium divisor disables invalid overtime rather than emitting NaN", () => {
    expect(compute({ ...overtime, premiumBaseMultiplier: Number.NaN }).gross).toBe(440);
  });

  test("legacy overlapping rules still select the highest rate", () => {
    const rules: SupplementRule[] = [
      { days: [7], from: "21:00", to: "06:00", rate: 28 },
      { days: [7], from: "00:00", to: "24:00", rate: 48 },
    ];
    expect(buildWagePeriods("22:00", "23:00", 7, 200, rules)[0].supplementRate).toBe(48);
    const grouped = rules.map((rule, index) => ({ ...rule, stackingGroup: String(index) }));
    expect(buildWagePeriods("22:00", "23:00", 7, 200, grouped)[0].supplementRate).toBe(76);
  });

  test("overlapping windows in one explicit group are not paid twice", () => {
    const rules: SupplementRule[] = [
      { days: [7], from: "21:00", to: "06:00", rate: 28, stackingGroup: "night" },
      { days: [7], from: "21:00", to: "24:00", rate: 30, stackingGroup: "night" },
      { days: [7], from: "00:00", to: "24:00", rate: 48, stackingGroup: "weekend" },
    ];
    expect(buildWagePeriods("22:00", "23:00", 7, 200, rules)[0].supplementRate).toBe(78);
  });

  test("KS-style percentage minimum and security fixed basis use the proper wage", () => {
    expect(buildWagePeriods("22:00", "23:00", 1, 200, [
      { days: weekdays, from: "21:00", to: "24:00", percent: 23, minimumRate: 73 },
    ])[0].supplementRate).toBe(73);
    expect(buildWagePeriods("22:00", "23:00", 1, 400, [
      { days: weekdays, from: "21:00", to: "24:00", percent: 100, percentageBaseRate: 246.22 },
    ])[0].supplementRate).toBe(246.22);
  });

  test("dated holiday-eve rules carry into the following morning only once", () => {
    const rules: SupplementRule[] = [
      { days: weekdays, from: "21:00", to: "06:00", rate: 100, dates: ["2026-12-24"] },
    ];
    expect(buildWagePeriods("02:00", "03:00", 5, 200, rules, "2026-12-25")[0].supplementRate).toBe(100);
    expect(buildWagePeriods("02:00", "03:00", 6, 200, rules, "2026-12-26")[0].supplementRate).toBe(0);
    expect(buildWagePeriods("02:00", "03:00", 5, 200, rules)[0].supplementRate).toBe(0);
  });

  test("holiday exclusions replace ordinary UB without affecting nearby weekdays", () => {
    const rules: SupplementRule[] = [
      { days: weekdays, from: "00:00", to: "24:00", rate: 20, excludedDates: ["2026-05-01"] },
      { days: weekdays, from: "00:00", to: "24:00", percent: 100, dates: ["2026-05-01"] },
    ];
    expect(buildWagePeriods("08:00", "09:00", 5, 200, rules, "2026-05-01")[0].supplementRate).toBe(200);
    expect(buildWagePeriods("08:00", "09:00", 4, 200, rules, "2026-04-30")[0].supplementRate).toBe(20);
  });

  test("Riksavtalen holiday premium follows the shift start date", () => {
    const rules: SupplementRule[] = [
      { days: weekdays, from: "00:00", to: "24:00", rate: 20,
        excludedShiftStartDates: ["2026-05-01"] },
      { days: weekdays, from: "00:00", to: "24:00", percent: 100,
        shiftStartDates: ["2026-05-01"] },
    ];
    const holidayShift = buildWagePeriods("22:00", "02:00", 5, 200, rules, "2026-05-01");
    expect(holidayShift.every((period) => period.supplementRate === 200)).toBe(true);
    const previousShift = buildWagePeriods("22:00", "02:00", 4, 200, rules, "2026-04-30");
    expect(previousShift.every((period) => period.supplementRate === 20)).toBe(true);
  });

  test("date anchors remain calendar dates through DST weekends", () => {
    const rules: SupplementRule[] = [
      { days: [6], from: "22:00", to: "06:00", rate: 70, dates: ["2026-10-24"] },
    ];
    expect(buildWagePeriods("02:00", "03:00", 7, 200, rules, "2026-10-25")[0].supplementRate).toBe(70);
  });
  test("dated overtime splits holiday-eve noon and does not leak to other dates", () => {
    const config: OvertimeConfig = { ...overtime, weeklyThresholdHours: 0.5, rules: [
      ...overtime.rules,
      { days: weekdays, from: "12:00", to: "24:00", percent: 400 / 3,
        appliesOnHolidays: true, dates: ["2026-12-24"] },
      { days: weekdays, from: "00:00", to: "24:00", percent: 400 / 3,
        appliesOnHolidays: false, dates: ["2026-12-25"] },
    ] };
    for (const [date, expected] of [["2026-12-23", 560], ["2026-12-24", 726.67], ["2026-12-25", 810]] satisfies [string, number][]) {
      const wage = snapshot(config);
      const row: ShiftRow = { id: "dated", user_id: "user", job_id: "job",
        shift_date: date, start_time: "11:00", end_time: "13:00" };
      const result = applyWeeklyOvertime([{ ...row, computed: computeShift(row, {}, [], wage) }], {
        snapshotForShift: () => wage, effectiveJobIdForShift: () => "job",
      })[0].computed;
      expect(result.gross).toBe(expected);
    }
  });

});

function computeRows(wage: WageSnapshot, rows: ShiftRow[]) {
  return applyWeeklyOvertime(rows.map((row) => ({
    ...row, computed: computeShift(row, {}, [], wage),
  })), { snapshotForShift: () => wage, effectiveJobIdForShift: () => "job" });
}

function row(date: string, start: string, end: string): ShiftRow {
  return { id: `${date}-${start}`, user_id: "user", job_id: "job",
    shift_date: date, start_time: start, end_time: end };
}

describe("overtime agreement exceptions", () => {
  test("explicitly removing all shift supplements also removes retained overtime additions", () => {
    const holiday: SupplementRule = { days: weekdays, from: "00:00", to: "24:00",
      percent: 100, dates: ["2027-03-27"] };
    const wage = snapshot({ ...overtime, retainedSupplements: [holiday] });
    wage.hourly_wage = 195.8;
    wage.supplements = { rules: [holiday] };
    const removed = { ...row("2027-03-27", "10:00", "11:00"), custom_supplements: { rules: [] } };
    const result = computeRows(wage, [row("2027-03-27", "09:00", "10:00"), removed]);
    expect(result[0].computed.gross).toBe(391.6);
    expect(result[1].computed.gross).toBe(293.7);
  });

  test("Handel holiday-eve premium survives overtime while ordinary UB stops", () => {
    const holiday: SupplementRule = { days: weekdays, from: "00:00", to: "24:00",
      percent: 100, dates: ["2027-03-27"], stackingGroup: "holiday" };
    const wage = snapshot({ ...overtime, retainedSupplements: [holiday] });
    wage.hourly_wage = 195.8;
    wage.supplements = { rules: [holiday,
      { days: weekdays, from: "00:00", to: "24:00", rate: 30, stackingGroup: "ordinary" }] };
    const result = computeRows(wage, [row("2027-03-27", "09:00", "10:00"),
      row("2027-03-27", "10:00", "11:00")]);
    expect(result[0].computed.gross).toBe(421.6);
    expect(result[1].computed.gross).toBe(489.5);
  });

  test("retained dated overnight rules split even when absent from ordinary periods", () => {
    const retained: SupplementRule = { days: weekdays, from: "23:00", to: "01:00",
      rate: 100, dates: ["2026-02-02"] };
    const wage = snapshot({ ...overtime, retainedSupplements: [retained] });
    const result = computeRows(wage, [row("2026-02-02", "22:00", "02:00")]);
    expect(result[0].computed.gross).toBe(1320);
  });

  test("cleaning apprentice overtime pays the adult base for the entire overtime hour", () => {
    const wage = snapshot({ ...overtime, baseRate: 247.29 });
    wage.hourly_wage = 133.08;
    wage.supplements = { rules: [] };
    const result = computeRows(wage, [row("2026-02-02", "08:00", "09:00"),
      row("2026-02-02", "09:00", "10:00")]);
    expect(result[0].computed.gross).toBe(133.08);
    expect(result[1].computed.gross).toBe(370.94);
    expect(result[1].computed.basePay).toBe(247.29);
  });

  test("cleaning retained percentage UB uses the adult overtime wage", () => {
    const holiday: SupplementRule = { days: weekdays, from: "00:00", to: "24:00", percent: 100 };
    const wage = snapshot({ ...overtime, baseRate: 247.29, retainedSupplements: [holiday],
      rules: overtime.rules.map((rule) => ({ ...rule, percent: 100 })) });
    wage.hourly_wage = 133.08;
    wage.supplements = { rules: [holiday] };
    const result = computeRows(wage, [row("2026-05-01", "07:00", "08:00"),
      row("2026-05-01", "08:00", "09:00")]);
    expect(result[0].computed.gross).toBe(266.16);
    expect(result[1].computed.gross).toBe(741.87);
  });

  test("Riks night guards retain whole-shift holiday pay only for starts before six", () => {
    const holiday: SupplementRule = { days: weekdays, from: "00:00", to: "24:00",
      percent: 100, shiftStartDates: ["2027-01-02"], shiftStartBefore: "06:00" };
    const wage = snapshot({ ...overtime, enabled: false });
    wage.supplements = { rules: [holiday,
      { days: weekdays, from: "21:00", to: "06:00", rate: 28 }] };
    for (const [start, end, gross] of [["00:00", "08:00", 3200],
      ["22:00", "06:00", 1824], ["06:00", "08:00", 400]] satisfies [string, string, number][]) {
      expect(computeRows(wage, [row("2027-01-02", start, end)])[0].computed.gross).toBe(gross);
    }
    wage.overtime = { ...overtime, retainSupplements: true, retainedSupplements: [holiday] };
    expect(computeRows(wage, [row("2027-01-02", "05:00", "08:00")])[0].computed.gross).toBe(1400);
  });
});
