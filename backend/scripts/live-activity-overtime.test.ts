import { describe, expect, test } from "bun:test";
import { computeLiveActivityShift, overtimeWeekStart } from "../convex/lib/shared/liveActivityPay";
import type { LiveActivityRecurringShift, LiveActivityRegularShift } from "../convex/lib/shared/liveActivityScheduling";
import type { OvertimeConfig, UserSettings, WageSnapshot } from "../convex/lib/shared/payroll/types";

const weekdays = [1, 2, 3, 4, 5, 6, 7];

function wage(weeklyThresholdHours: number): WageSnapshot {
  const overtime: OvertimeConfig = {
    enabled: true,
    weeklyThresholdHours,
    rules: [
      { days: weekdays, from: "00:00", to: "24:00", percent: 50, appliesOnHolidays: false },
      { days: weekdays, from: "00:00", to: "24:00", percent: 50, appliesOnHolidays: true },
    ],
  };
  return {
    id: "wage", user_id: "user", job_id: "job", from_date: null,
    hourly_wage: 200, wage_level: null, tariff_type_id: null,
    supplements: { rules: [] },
    overtime, tax_enabled: false, tax_percentage: 0,
    break_enabled: false, break_method: "none", break_threshold_hours: 0, break_deduction_minutes: 0,
  } as WageSnapshot;
}

const shift = (id: string, shift_date: string, start_time: string, end_time: string): LiveActivityRegularShift => ({
  id, user_id: "user", job_id: "job", shift_date, start_time, end_time,
  custom_pause_windows: null, custom_supplements: null,
});

// 2026-02-02 is a Monday. The target shift is two hours on Tuesday.
const target = shift("target", "2026-02-03", "08:00", "10:00");

function liveActivityPay(
  threshold: number,
  regular: LiveActivityRegularShift[],
  recurring: LiveActivityRecurringShift[] = [],
) {
  const snapshot = wage(threshold);
  return computeLiveActivityShift(target, [target, ...regular], recurring, () => snapshot, {} as UserSettings);
}

describe("Live Activity pay includes weekly overtime", () => {
  test("the overtime week starts on the Sunday before its Monday", () => {
    expect(overtimeWeekStart("2026-02-03")).toBe("2026-02-01");
    expect(overtimeWeekStart("2026-02-02")).toBe("2026-02-01");
    expect(overtimeWeekStart("2026-02-08")).toBe("2026-02-01");
  });

  test("a shift alone under the threshold is paid at the base rate", () => {
    const pay = liveActivityPay(4, []);
    expect(pay.overtimeMinutes).toBe(0);
    expect(pay.gross).toBe(400);
  });

  test("earlier hours that week push the shift into overtime", () => {
    const pay = liveActivityPay(4, [shift("monday", "2026-02-02", "08:00", "12:00")]);
    expect(pay.overtimeMinutes).toBe(120);
    expect(pay.gross).toBe(600);
  });

  test("hours after midnight on the Sunday before count toward the week", () => {
    const pay = liveActivityPay(4, [shift("sunday-night", "2026-02-01", "20:00", "04:00")]);
    expect(pay.overtimeMinutes).toBe(120);
  });

  test("a Sunday day shift belongs to the previous week", () => {
    const pay = liveActivityPay(4, [shift("sunday-day", "2026-02-01", "08:00", "12:00")]);
    expect(pay.overtimeMinutes).toBe(0);
  });

  test("overlapping shifts on one date count once", () => {
    const pay = liveActivityPay(6, [
      shift("monday-a", "2026-02-02", "08:00", "12:00"),
      shift("monday-b", "2026-02-02", "09:00", "13:00"),
    ]);
    // 4 counted hours on Monday + 2 on Tuesday is 6, so nothing is over the threshold.
    expect(pay.overtimeMinutes).toBe(0);
  });

  test("recurring shifts earlier in the week count", () => {
    const recurring: LiveActivityRecurringShift = {
      id: "weekly", user_id: "user", job_id: "job", start_time: "08:00", end_time: "12:00",
      repeat_interval_weeks: 0, selected_days: { "1": "2026-01-05" }, end_condition: null, exclusions: null,
    };
    const pay = liveActivityPay(4, [], [recurring]);
    expect(pay.overtimeMinutes).toBe(120);
  });

  test("shifts later in the week do not change an earlier shift", () => {
    const pay = liveActivityPay(1, [shift("thursday", "2026-02-05", "08:00", "18:00")]);
    expect(pay.overtimeMinutes).toBe(60);
  });
});
