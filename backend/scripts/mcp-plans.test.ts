import { describe, expect, test } from "bun:test";
import { checkColumns } from "../convex/lib/columns";
import {
  adjustmentFields,
  changedEvent,
  eventFields,
  saveEvent,
  savePayrollAdjustment,
  updateSettings,
} from "../convex/lib/mcp/plans";
import {
  overlappingDates,
  planOccurrence,
  previewEnd,
  sameSeries,
  saveRecurringShift,
  type Series,
  seriesDates,
  seriesUpdate,
  storedEndCondition,
} from "../convex/lib/mcp/recurring";
import { addDays } from "../convex/lib/mcp/shiftTimes";

// Dates near today, so the five-year check on tool arguments passes in any year.
const MONDAY = (() => {
  const today = new Date().toISOString().slice(0, 10);
  const weekday = new Date(`${today}T00:00:00Z`).getUTCDay();
  return addDays(today, ((8 - weekday) % 7) + 7);
})();
const WEDNESDAY = addDays(MONDAY, 2);

function series(args: Record<string, unknown>): Series & { start_time: string; end_time: string } {
  const parsed = saveRecurringShift.parse({ start: "08:00", end: "16:00", ...args });
  if (parsed.mode !== "create") throw new Error("expected create");
  return { ...parsed, exclusions: [] };
}

describe("recurring shifts", () => {
  test("a weekly series on Monday and Wednesday has those dates until end_date, the end date included", () => {
    const s = series({ first_dates: [MONDAY, WEDNESDAY], end_date: addDays(MONDAY, 14) });
    expect(seriesDates(s, addDays(MONDAY, -7), addDays(MONDAY, 60))).toEqual([
      MONDAY,
      WEDNESDAY,
      addDays(MONDAY, 7),
      addDays(WEDNESDAY, 7),
      addDays(MONDAY, 14),
    ]);
  });

  test("every second week counts each weekday from its own first date", () => {
    const s = series({ first_dates: [MONDAY, addDays(WEDNESDAY, 7)], every_weeks: 2 });
    expect(seriesDates(s, MONDAY, addDays(MONDAY, 27))).toEqual([MONDAY, addDays(WEDNESDAY, 7), addDays(MONDAY, 14), addDays(WEDNESDAY, 21)]);
  });

  test("two first dates on the same weekday are refused", () => {
    expect(() => series({ first_dates: [MONDAY, addDays(MONDAY, 7)] })).toThrow("two Mondays");
  });

  test("multiple flat end fields at once are refused", () => {
    expect(() => series({ first_dates: [MONDAY], end_date: addDays(MONDAY, 14), end_after_months: 2 })).toThrow("at most one");
  });

  test("a series that ends at midnight is stored as 24:00, as the app sends it, and the server accepts it", () => {
    const s = series({ first_dates: [MONDAY], start: "16:00", end: "24:00" });
    expect(s.end_time).toBe("24:00");
    expect(() => checkColumns("recurring_shifts", { start_time: s.start_time, end_time: s.end_time })).not.toThrow();
  });

  test("skipping one date removes only that date", () => {
    const s = series({ first_dates: [MONDAY] });
    const plan = planOccurrence({ ...s, date_specific_notes: {} }, addDays(MONDAY, 7), { kind: "skip" });
    const after = seriesDates({ ...s, exclusions: plan.exclusions! }, MONDAY, addDays(MONDAY, 21));
    expect(after).toEqual([MONDAY, addDays(MONDAY, 14), addDays(MONDAY, 21)]);
    expect(plan).not.toHaveProperty("shift");
  });

  test("changing a date's times takes it out of the series and adds a one-off shift that keeps the date's note", () => {
    const s = series({ first_dates: [MONDAY] });
    const date = addDays(MONDAY, 7);
    const plan = planOccurrence({ ...s, date_specific_notes: { [date]: "Cover for Ola" } }, date, { kind: "change", start: "10:00" });
    expect(plan.shift).toEqual({ shift_date: date, start_time: "10:00", end_time: "18:00", note: "Cover for Ola" });
    expect(plan.exclusions).toEqual([date]);
    expect(plan.date_specific_notes).toBeNull();
    expect(seriesDates({ ...s, exclusions: plan.exclusions! }, date, date)).toEqual([]);
  });

  test("a note alone keeps the date in the series", () => {
    const s = series({ first_dates: [MONDAY] });
    expect(planOccurrence({ ...s, date_specific_notes: {} }, MONDAY, { kind: "note", note: " Bring keys " })).toEqual({
      date_specific_notes: { [MONDAY]: "Bring keys" },
    });
    expect(planOccurrence({ ...s, date_specific_notes: { [MONDAY]: "old" } }, MONDAY, { kind: "change", start: "08:00", note: "" })).toEqual({
      date_specific_notes: null,
    });
  });

  test("a new series skips dates where the user already works, including the morning after a night shift", () => {
    const s = series({ first_dates: [MONDAY, WEDNESDAY], end_after_months: 1 });
    const dates = seriesDates(s, MONDAY, previewEnd(s));
    const existing = [
      { date: addDays(MONDAY, 7), start: "12:00:00", end: "14:00:00" },
      { date: addDays(WEDNESDAY, 13), start: "22:00", end: "09:00" },
      { date: addDays(WEDNESDAY, 21), start: "16:00", end: "20:00" },
    ];
    expect(overlappingDates(dates, s.start_time, s.end_time, existing)).toEqual([addDays(MONDAY, 7), addDays(WEDNESDAY, 14)]);
  });

  test("a new night series clashes with an early shift the next morning", () => {
    const early = [{ date: addDays(MONDAY, 8), start: "05:00", end: "09:00" }];
    expect(overlappingDates([MONDAY, addDays(MONDAY, 7)], "22:00", "06:00", early)).toEqual([addDays(MONDAY, 7)]);
  });

  test("a series with no end checks two years ahead for clashes, as the app's preview does", () => {
    const s = series({ first_dates: [MONDAY] });
    expect(previewEnd(s)).toBe(`${Number(MONDAY.slice(0, 4)) + 2}${MONDAY.slice(4)}`);
  });

  test("a new start keeps the shift's length, and never_ends removes the end", () => {
    const s = { ...series({ first_dates: [MONDAY], start: "22:00", end: "06:00", end_after_years: 1 }), end_time: "06:00:00+00" };
    const change = saveRecurringShift.parse({ id: "r", start: "18:00", never_ends: true });
    if (change.mode !== "update") throw new Error("expected update");
    expect(seriesUpdate(s, change)).toEqual({ set: { start_time: "18:00", end_time: "02:00" }, clear: ["end_condition"] });
  });

  test("stopping a series sets end_date cleanly via save_recurring_shift", () => {
    const s = series({ first_dates: [MONDAY], end_after_months: 2 });
    const change = saveRecurringShift.parse({ id: "r", end_date: addDays(MONDAY, 7) });
    if (change.mode !== "update") throw new Error("expected update");
    const update = seriesUpdate(s, change);
    expect(update.set.end_condition).toEqual({ type: "end_date", date: addDays(MONDAY, 7) });
    expect(() => seriesUpdate(s, { end_condition: { value: { type: "end_date", date: addDays(MONDAY, -1) } } })).toThrow("delete_recurring_shift");
  });

  test("adding the same series again is recognised, whatever the stored time format or weekday order", () => {
    const added = series({ first_dates: [MONDAY, WEDNESDAY], start: "16:00", end: "24:00", end_after_months: 3 });
    const stored = {
      ...series({ first_dates: [WEDNESDAY, MONDAY], start: "16:00", end: "00:00", end_after_months: 3 }),
      start_time: "16:00:00+00",
      end_time: "00:00:00+00",
      exclusions: [MONDAY],
    };
    expect(sameSeries(stored, added)).toBe(true);
    expect(sameSeries({ ...stored, repeat_interval_weeks: 1 }, added)).toBe(false);
  });

  test("the older stored end_date form is read the same as the new one", () => {
    expect(storedEndCondition({ type: "end_date", value: "2026-12-31" })).toEqual({ type: "end_date", date: "2026-12-31" });
    expect(storedEndCondition(undefined)).toBeNull();
  });
});

describe("events", () => {
  const createEvent = (args: Record<string, unknown>) => {
    const res = saveEvent.parse(args);
    if (res.mode !== "create") throw new Error("expected create");
    return res.fields;
  };

  test("an all-day reminder without a reminder time is refused", () => {
    expect(() => createEvent({ note: "Exam", date: MONDAY, reminder_days_before: [1] })).toThrow("reminder_time is required");
  });

  test("all-day reminders are stored as whole days before, largest first, with the clock time", () => {
    expect(createEvent({ note: " Exam ", date: MONDAY, end_date: WEDNESDAY, reminder_days_before: [0, 2], reminder_time: "09:00" })).toEqual({
      start_date: MONDAY,
      end_date: WEDNESDAY,
      is_all_day: true,
      note: "Exam",
      notification_minutes_array: [2880, 0],
      notification_anchor_time: "09:00",
    });
  });

  test("a timed event can't run past midnight, but may end at 24:00", () => {
    expect(() => createEvent({ note: "Party", date: MONDAY, start: "22:00", end: "02:00" })).toThrow("past midnight");
    expect(createEvent({ note: "Party", date: MONDAY, start: "22:00", end: "24:00", reminder_minutes: [15, 60] })).toMatchObject({
      end_time: "24:00",
      notification_minutes_array: [60, 15],
    });
  });

  test("a timed event refuses all-day reminders", () => {
    expect(() => createEvent({ note: "Call", date: MONDAY, start: "10:00", end: "11:00", reminder_days_before: [1] })).toThrow();
  });

  test("making a timed event all-day drops its minute reminders", () => {
    const timed = eventFields({ note: "Call", date: MONDAY, start: "10:00", end: "11:00", reminder_minutes: [30] });
    expect(eventFields(changedEvent(timed, { all_day: true }))).toEqual({ start_date: MONDAY, end_date: MONDAY, is_all_day: true, note: "Call" });
  });

  test("moving an all-day event keeps its length and reminders", () => {
    const trip = eventFields({ note: "Trip", date: MONDAY, end_date: WEDNESDAY, reminder_days_before: [1], reminder_time: "18:00" });
    expect(eventFields(changedEvent(trip, { date: addDays(MONDAY, 7) }))).toEqual({
      ...trip,
      start_date: addDays(MONDAY, 7),
      end_date: addDays(WEDNESDAY, 7),
    });
  });
});

describe("payroll adjustments", () => {
  const created = savePayrollAdjustment.parse({ amount: 1500, description: " Christmas bonus ", category: "bonus", payout_date: MONDAY });
  if (created.mode !== "create") throw new Error("expected create");

  test("an adjustment on a job whose pay has no tax is paid out as is, in the job's currency", () => {
    expect(adjustmentFields({ ...created, tax_treatment: "gross_taxable" }, { id: "job", currency: "€", taxEnabled: false })).toEqual({
      job_id: "job",
      amount: 1500,
      currency: "€",
      category: "bonus",
      tax_treatment: "net_manual",
      description: "Christmas bonus",
      payout_date: MONDAY,
    });
  });

  test("an adjustment on a taxed job is taxed like pay unless told otherwise", () => {
    expect(adjustmentFields(created, { id: "job", currency: "kr", taxEnabled: true }).tax_treatment).toBe("gross_taxable");
  });

  test("a zero amount, a half earned range and a backwards earned range are refused", () => {
    expect(() => savePayrollAdjustment.parse({ amount: 0, description: "x", payout_date: MONDAY })).toThrow("other than 0");
    expect(() => savePayrollAdjustment.parse({ amount: 1, description: "x", payout_date: MONDAY, earned_from: MONDAY })).toThrow("both");
    expect(() =>
      savePayrollAdjustment.parse({ amount: 1, description: "x", payout_date: MONDAY, earned_from: WEDNESDAY, earned_to: MONDAY }),
    ).toThrow("after earned_to");
  });
});

describe("settings", () => {
  test("settings are routed to the table that stores them, and an unknown time zone is refused", () => {
    expect(updateSettings.parse({ theme: "dark", time_zone: "Europe/Oslo" })).toEqual({
      user_settings: { theme: "dark" },
      schedule_time_zone: "Europe/Oslo",
    });
    expect(() => updateSettings.parse({ time_zone: "CET+1" })).toThrow("IANA");
    expect(() => updateSettings.parse({ startup_tab: "add" })).toThrow();
  });

  test("notification settings can't be changed, because the phone keeps its own copy", () => {
    expect(() => updateSettings.parse({ shift_reminder_minutes: [] })).toThrow("shift_reminder_minutes");
  });
});
