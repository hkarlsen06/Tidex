import { assertEquals } from "jsr:@std/assert";

import { applyCustomPauseWindowClipping, normalizeCustomPauseWindows } from "./pause-windows.ts";
import type { WagePeriod } from "./types.ts";

Deno.test("normalizeCustomPauseWindows drops invalid and duplicate windows", () => {
  const normalized = normalizeCustomPauseWindows({
    windows: [
      { start: "12:00", end: "12:30" },
      { start: "12:00", end: "12:30" },
      { start: "25:00", end: "12:30" },
      { start: "14:00", end: "14:00" },
      { start: "23:30", end: "00:00" },
    ],
  });

  assertEquals(normalized, {
    windows: [
      { start: "12:00", end: "12:30" },
      { start: "23:30", end: "00:00" },
    ],
  });
});

Deno.test("applyCustomPauseWindowClipping clips exact pauses across midnight", () => {
  const periods: WagePeriod[] = [
    { fromMin: 21 * 60, toMin: (24 * 60) + (5 * 60), baseRate: 200, supplementRate: 0, totalRate: 200 },
  ];

  const result = applyCustomPauseWindowClipping(
    periods,
    {
      windows: [
        { start: "22:00", end: "22:30" },
        { start: "00:15", end: "00:45" },
        { start: "08:00", end: "08:30" },
      ],
    },
    "21:00",
    "05:00",
  );

  assertEquals(result.periods, [
    { fromMin: 21 * 60, toMin: 22 * 60, baseRate: 200, supplementRate: 0, totalRate: 200 },
    { fromMin: (22 * 60) + 30, toMin: (24 * 60) + 15, baseRate: 200, supplementRate: 0, totalRate: 200 },
    { fromMin: (24 * 60) + 45, toMin: (24 * 60) + (5 * 60), baseRate: 200, supplementRate: 0, totalRate: 200 },
  ]);
  assertEquals(result.deductedHours, 1);
  assertEquals(result.appliedPauseWindows, [
    { start: "22:00", end: "22:30" },
    { start: "00:15", end: "00:45" },
  ]);
});
