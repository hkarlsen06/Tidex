import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applicableWageSnapshot,
  presentationForShift,
} from "./live-activity-delivery.ts";

const shift = {
  id: "shift-1",
  user_id: "user-1",
  job_id: "job-1",
  shift_date: "2026-07-20",
  start_time: "08:00",
  end_time: "16:00",
};

function snapshot(
  id: string,
  jobId: string,
  fromDate: string | null,
  hourly: number,
) {
  return {
    id,
    user_id: "user-1",
    job_id: jobId,
    from_date: fromDate,
    hourly_wage: hourly,
    wage_level: null,
    tariff_type_id: null,
    supplements: { rules: [] },
    tax_enabled: true,
    tax_percentage: 25,
    break_enabled: false,
    break_method: "none" as const,
    break_threshold_hours: 5.5,
    break_deduction_minutes: 30,
  };
}

Deno.test("applicable snapshot is scoped to the shift job and effective date", () => {
  const selected = applicableWageSnapshot(shift, [
    snapshot("other-job", "job-2", "2026-07-01", 999),
    snapshot("baseline", "job-1", null, 200),
    snapshot("current", "job-1", "2026-07-01", 250),
    snapshot("future", "job-1", "2026-08-01", 300),
  ]);
  assertEquals(selected?.id, "current");
});

Deno.test("presentation matches payroll, tax, currency, and timezone inputs", () => {
  const presentation = presentationForShift(
    shift,
    "Europe/Oslo",
    { user_id: "user-1", currency: "kr" },
    [snapshot("current", "job-1", null, 250)],
  );
  assertEquals(presentation.hourly, 250);
  assertEquals(presentation.supplement, 0);
  assertEquals(presentation.gross, 2_000);
  assertEquals(presentation.net, 1_500);
  assertEquals(presentation.currency, "kr");
  assertEquals(
    presentation.startDate.toISOString(),
    "2026-07-20T06:00:00.000Z",
  );
  assertEquals(presentation.endDate.toISOString(), "2026-07-20T14:00:00.000Z");
});
