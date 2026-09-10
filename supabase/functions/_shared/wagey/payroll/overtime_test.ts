import { assertEquals } from "jsr:@std/assert";

import { applyWeeklyOvertime, computeShift } from "./calc.ts";
import type {
  OvertimeConfig,
  ShiftRow,
  ShiftWithComputations,
  WageSnapshot,
} from "./types.ts";

const overtime: OvertimeConfig = {
  enabled: true,
  weeklyThresholdHours: 40,
  rules: [
    {
      days: [1, 2, 3, 4, 5, 6],
      appliesOnHolidays: false,
      from: "00:00",
      to: "21:00",
      percent: 50,
    },
    {
      days: [1, 2, 3, 4, 5, 6],
      appliesOnHolidays: false,
      from: "21:00",
      to: "24:00",
      percent: 100,
    },
    {
      days: [7],
      appliesOnHolidays: true,
      from: "00:00",
      to: "24:00",
      percent: 100,
    },
    {
      days: [1, 2, 3, 4, 5, 6, 7],
      appliesOnHolidays: true,
      from: "00:00",
      to: "24:00",
      percent: 100,
    },
  ],
};

Deno.test("applyWeeklyOvertime splits at threshold and replaces custom supplements", () => {
  const snapshot = makeSnapshot({ overtime });
  const customSupplements = {
    rules: [{
      from: "16:00" as const,
      to: "22:00" as const,
      rate: 1_000,
    }],
  };
  const shifts = [
    makeComputedShift(snapshot, "mon", "2026-02-02", "08:00", "17:30"),
    makeComputedShift(snapshot, "tue", "2026-02-03", "08:00", "17:30"),
    makeComputedShift(snapshot, "wed", "2026-02-04", "08:00", "17:30"),
    makeComputedShift(snapshot, "thu", "2026-02-05", "08:00", "17:30"),
    makeComputedShift(
      snapshot,
      "fri",
      "2026-02-06",
      "16:00",
      "22:00",
      customSupplements,
    ),
  ];

  const adjusted = applyWeeklyOvertime(shifts, {
    snapshotForShift: () => snapshot,
    effectiveJobIdForShift: () => "job-a",
  });
  const friday = adjusted.find((shift) => shift.id === "fri");

  assertEquals(friday?.computed.overtimeMinutes, 240);
  assertEquals(friday?.computed.basePay, 1_200);
  assertEquals(friday?.computed.supplementPay, 2_500);
  assertEquals(friday?.computed.gross, 3_700);
});

Deno.test("Sunday overtime stays before Monday's weekly reset", () => {
  const snapshot = makeSnapshot({ overtime });
  const shifts = [
    makeComputedShift(snapshot, "mon", "2026-02-02", "08:00", "18:00"),
    makeComputedShift(snapshot, "tue", "2026-02-03", "08:00", "18:00"),
    makeComputedShift(snapshot, "wed", "2026-02-04", "08:00", "18:00"),
    makeComputedShift(snapshot, "thu", "2026-02-05", "08:00", "18:00"),
    makeComputedShift(snapshot, "sun", "2026-02-08", "22:00", "02:00"),
  ];
  const sunday = applyWeeklyOvertime(shifts, {
    snapshotForShift: () => snapshot,
    effectiveJobIdForShift: () => "job-a",
  }).find((shift) => shift.id === "sun")!;
  const periods = sunday.computed.wagePeriods.filter((period) => period.isOvertime);
  assertEquals(sunday.computed.overtimeMinutes, 120);
  assertEquals(periods[0].fromMin, 22 * 60);
  assertEquals(periods.at(-1)?.toMin, 24 * 60);
});

Deno.test("equal ordinary and overtime rates keep their distinct classification", () => {
  const snapshot = makeSnapshot({ overtime: { ...overtime, weeklyThresholdHours: 1 } });
  snapshot.supplements = { rules: [{ days: [7], from: "00:00", to: "24:00", rate: 200 }] };
  const [sunday] = applyWeeklyOvertime([
    makeComputedShift(snapshot, "sun", "2026-02-08", "08:00", "10:00"),
  ], {
    snapshotForShift: () => snapshot,
    effectiveJobIdForShift: () => "job-a",
  });
  assertEquals(sunday.computed.wagePeriods.length, 2);
  assertEquals(sunday.computed.wagePeriods[0].isOvertime, false);
  assertEquals(sunday.computed.wagePeriods[1].isOvertime, true);
});

function makeComputedShift(
  snapshot: WageSnapshot,
  id: string,
  shift_date: string,
  start_time: string,
  end_time: string,
  custom_supplements?: ShiftRow["custom_supplements"],
): ShiftWithComputations {
  const shift: ShiftRow = {
    id,
    user_id: "user-1",
    job_id: "job-a",
    shift_date,
    start_time,
    end_time,
    custom_supplements,
  };
  return {
    ...shift,
    computed: computeShift(shift, {}, [], snapshot),
    tax_enabled: false,
    tax_percentage: 0,
  };
}

function makeSnapshot(params: { overtime: OvertimeConfig }): WageSnapshot {
  return {
    id: "snapshot-1",
    user_id: "user-1",
    job_id: "job-a",
    from_date: null,
    hourly_wage: 200,
    wage_level: null,
    tariff_type_id: null,
    supplements: { rules: [] },
    overtime: params.overtime,
    tax_enabled: false,
    tax_percentage: 0,
    break_enabled: false,
    break_method: "none",
    break_threshold_hours: 0,
    break_deduction_minutes: 0,
  };
}
