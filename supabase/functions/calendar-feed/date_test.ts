// deno-lint-ignore-file no-import-prefix
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createFeedWindow } from "./date.ts";

Deno.test("createFeedWindow spans 18 months behind and 6 months ahead", () => {
  assertEquals(
    createFeedWindow(new Date("2026-05-17T10:00:00Z")),
    {
      startDate: "2024-11-17",
      endDate: "2026-11-17",
    },
  );
});

Deno.test("createFeedWindow clamps month-end dates", () => {
  assertEquals(
    createFeedWindow(new Date("2026-08-31T10:00:00Z"), "UTC"),
    {
      startDate: "2025-02-28",
      endDate: "2027-02-28",
    },
  );
});
