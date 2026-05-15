// deno-lint-ignore-file no-import-prefix
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildICalendarFeed,
  escapeICalendarText,
  foldICalendarLine,
} from "./ics.ts";

Deno.test("foldICalendarLine folds UTF-8 byte-aware lines without splitting multibyte text", () => {
  const folded = foldICalendarLine(`SUMMARY:${"å".repeat(40)}`);
  const lines = folded.split("\r\n");

  assert(lines.length > 1);
  for (const line of lines) {
    assert(new TextEncoder().encode(line).byteLength <= 75);
  }
  assertEquals(folded.replaceAll("\r\n ", ""), `SUMMARY:${"å".repeat(40)}`);
});

Deno.test("escapeICalendarText escapes special text values", () => {
  assertEquals(
    escapeICalendarText("Hei, Oslo; test\\line\nnext"),
    "Hei\\, Oslo\\; test\\\\line\\nnext",
  );
});

Deno.test("buildICalendarFeed emits all-day exclusive DTEND and floating timed values", async () => {
  const feed = await buildICalendarFeed(
    {
      jobs: [],
      shifts: [],
      recurringShifts: [],
      events: [
        {
          id: "event-1",
          start_date: "2026-05-14",
          end_date: "2026-05-15",
          is_all_day: true,
          start_time: null,
          end_time: null,
          note: "Fri",
          updated_at: "2026-05-14T10:00:00Z",
        },
        {
          id: "event-2",
          start_date: "2026-05-16",
          end_date: "2026-05-16",
          is_all_day: false,
          start_time: "09:00:00+02:00",
          end_time: "10:30:00+02:00",
          note: "Lege",
          updated_at: "2026-05-14T10:00:00Z",
        },
      ],
    },
    [],
    { startDate: "2026-05-01", endDate: "2026-06-01" },
  );

  assertStringIncludes(feed, "DTSTART;VALUE=DATE:20260514");
  assertStringIncludes(feed, "DTEND;VALUE=DATE:20260516");
  assertStringIncludes(feed, "DTSTART:20260516T090000");
  assertStringIncludes(feed, "DTEND:20260516T103000");
});

Deno.test("buildICalendarFeed applies cross-midnight handling only to shifts", async () => {
  const feed = await buildICalendarFeed(
    {
      jobs: [{ id: "job-1", name: "Night" }],
      shifts: [
        {
          id: "shift-1",
          shift_date: "2026-05-14",
          start_time: "22:00:00+02:00",
          end_time: "06:00:00+02:00",
          note: "Natt",
          job_id: "job-1",
          recurring_id: null,
          updated_at: "2026-05-14T10:00:00Z",
        },
      ],
      recurringShifts: [],
      events: [],
    },
    [],
    { startDate: "2026-05-01", endDate: "2026-06-01" },
  );

  assertStringIncludes(feed, "SUMMARY:Shift: Night");
  assertStringIncludes(feed, "DESCRIPTION:Natt");
  assertStringIncludes(feed, "DTSTART:20260514T220000");
  assertStringIncludes(feed, "DTEND:20260515T060000");
});

Deno.test("buildICalendarFeed localizes shift summaries", async () => {
  const feed = await buildICalendarFeed(
    {
      jobs: [{ id: "job-1", name: "Extra" }],
      shifts: [
        {
          id: "shift-1",
          shift_date: "2026-05-14",
          start_time: "09:00:00+02:00",
          end_time: "17:00:00+02:00",
          note: null,
          job_id: "job-1",
          recurring_id: null,
          updated_at: "2026-05-14T10:00:00Z",
        },
      ],
      recurringShifts: [],
      events: [],
    },
    [],
    { startDate: "2026-05-01", endDate: "2026-06-01" },
    "nb",
  );

  assertStringIncludes(feed, "SUMMARY:Vakt: Extra");
});
