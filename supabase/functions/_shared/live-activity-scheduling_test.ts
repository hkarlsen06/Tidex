import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  findOngoingShift,
  isShiftOngoingAtLocalClock,
  localClock,
  normalizeStoredTime,
  zonedShiftRange,
} from "./live-activity-scheduling.ts";

Deno.test("normalizes Postgres timetz values", () => {
  assertEquals(normalizeStoredTime("08:15:00+02:00"), "08:15");
});

Deno.test("ongoing shift boundaries are start inclusive and end exclusive", () => {
  const shift = {
    shift_date: "2026-07-20",
    start_time: "08:00",
    end_time: "16:00",
  };
  assertEquals(
    isShiftOngoingAtLocalClock(shift, {
      date: "2026-07-20",
      previousDate: "2026-07-19",
      minuteOfDay: 8 * 60,
    }),
    true,
  );
  assertEquals(
    isShiftOngoingAtLocalClock(shift, {
      date: "2026-07-20",
      previousDate: "2026-07-19",
      minuteOfDay: 16 * 60,
    }),
    false,
  );
});

Deno.test("cross-midnight shifts remain ongoing on the following date", () => {
  assertEquals(
    isShiftOngoingAtLocalClock(
      { shift_date: "2026-07-20", start_time: "22:00", end_time: "06:00" },
      {
        date: "2026-07-21",
        previousDate: "2026-07-20",
        minuteOfDay: 5 * 60 + 59,
      },
    ),
    true,
  );
});

Deno.test("local clock resolves the installation timezone", () => {
  assertEquals(localClock(new Date("2026-07-20T22:30:00Z"), "Europe/Oslo"), {
    date: "2026-07-21",
    previousDate: "2026-07-20",
    minuteOfDay: 30,
  });
});

Deno.test("a regular shift suppresses a recurring occurrence on the same date", () => {
  const ongoing = findOngoingShift(
    new Date("2026-07-20T10:00:00Z"),
    "UTC",
    [{
      id: "regular",
      user_id: "user",
      job_id: "job",
      shift_date: "2026-07-20",
      start_time: "12:00",
      end_time: "13:00",
    }],
    [{
      id: "series",
      user_id: "user",
      job_id: "job",
      start_time: "08:00:00+00",
      end_time: "16:00:00+00",
      repeat_interval_weeks: 0,
      selected_days: { "1": "2026-07-06" },
      end_condition: null,
      exclusions: [],
    }],
  );
  assertEquals(ongoing, null);
});

Deno.test("zoned range preserves Oslo wall clock during daylight saving time", () => {
  const range = zonedShiftRange(
    { shift_date: "2026-07-20", start_time: "08:00", end_time: "16:00" },
    "Europe/Oslo",
  );
  assertEquals(range.startDate.toISOString(), "2026-07-20T06:00:00.000Z");
  assertEquals(range.endDate.toISOString(), "2026-07-20T14:00:00.000Z");
});
