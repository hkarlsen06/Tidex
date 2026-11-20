import { describe, expect, test } from "bun:test";
import { generateVirtualShiftsForMonth } from "../convex/lib/shared/recurring/utils";

// The app ends a "for N months" schedule with Foundation's month arithmetic, which stops
// on the last day of a shorter month instead of rolling into the next one.
describe("recurring schedules that end after a number of months", () => {
  // 2027-01-31 is a Sunday and 2027-02-01 a Monday.
  const oneMonth = {
    start_time: "08:00",
    end_time: "12:00",
    repeat_interval_weeks: 0 as const,
    selected_days: { "0": "2027-01-31", "1": "2027-02-01" },
    end_condition: { type: "months" as const, value: 1 },
    exclusions: [],
  };

  test("a schedule from 31 January ends on 28 February, as in the app", () => {
    const february = generateVirtualShiftsForMonth({ year: 2027, month: 2 }, oneMonth).map((s) => s.date);
    expect(february).toContain("2027-02-28");
    expect(generateVirtualShiftsForMonth({ year: 2027, month: 3 }, oneMonth)).toEqual([]);
  });

  test("a yearly end from 29 February stops on 28 February the next year", () => {
    // 2028-02-29 is a Tuesday. 2029-03-01 is a Thursday, the day after the app's end.
    const oneYear = {
      ...oneMonth,
      selected_days: { "2": "2028-02-29", "4": "2028-03-02" },
      end_condition: { type: "years" as const, value: 1 },
    };
    expect(generateVirtualShiftsForMonth({ year: 2029, month: 2 }, oneYear).map((s) => s.date)).toContain("2029-02-27");
    expect(generateVirtualShiftsForMonth({ year: 2029, month: 3 }, oneYear)).toEqual([]);
  });
});
