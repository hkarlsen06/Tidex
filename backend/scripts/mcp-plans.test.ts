import { describe, expect, test } from "bun:test";
import { checkColumns } from "../convex/lib/columns";
import {
  addEvent,
  addPayrollAdjustment,
  adjustmentFields,
  changedEvent,
  eventFields,
  reminderSettings,
  updateSettings,
} from "../convex/lib/mcp/plans";
import {
  addRecurringShift,
  changeRecurringOccurrence,
  overlappingDates,
  planOccurrence,
  previewEnd,
  sameSeries,
  type Series,
  seriesDates,
  seriesUpdate,
  stoppedEnd,
  storedEndCondition,
  updateRecurringShift,
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
  const parsed = addRecurringShift.parse({ start: "08:00", end: "16:00", ...args });
  return { ...parsed, exclusions: [] };
}

const weekdays = (dates: string[]) => dates.map((d) => new Date(`${d}T00:00:00Z`).getUTCDay());

describe("recurring shifts", () => {
  test("a weekly series on Monday and Wednesday has those dates until its end date, the end date included", () => {
    const s = series({ first_dates: [MONDAY, WEDNESDAY], ends: { type: "end_date", date: addDays(MONDAY, 14) } });
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

  test("a series that ends at midnight is stored so the server's time column accepts it, and ends the next day", () => {
    const s = series({ first_dates: [MONDAY], start: "16:00", end: "24:00" });
    expect(s.end_time).toBe("00:00");
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
    const { change } = changeRecurringOccurrence.parse({ recurring_shift_id: "r", revision: 1, date, start: "10:00" });
    const plan = planOccurrence({ ...s, date_specific_notes: { [date]: "Cover for Ola" } }, date, change);
    expect(plan.shift).toEqual({ shift_date: date, start_time: "10:00", end_time: "18:00", note: "Cover for Ola" });
    expect(plan.exclusions).toEqual([date]);
    expect(plan.date_specific_notes).toBeNull();
    expect(seriesDates({ ...s, exclusions: plan.exclusions! }, date, date)).toEqual([]);
  });

  test("a note alone keeps the date in the series", () => {
    const s = series({ first_dates: [MONDAY] });
    const { change } = changeRecurringOccurrence.parse({ recurring_shift_id: "r", revision: 1, date: MONDAY, note: " Bring keys " });
    expect(planOccurrence({ ...s, date_specific_notes: {} }, MONDAY, change)).toEqual({ date_specific_notes: { [MONDAY]: "Bring keys" } });
    const sameTimes = changeRecurringOccurrence.parse({ recurring_shift_id: "r", revision: 1, date: MONDAY, start: "08:00", note: "" });
    expect(planOccurrence({ ...s, date_specific_notes: { [MONDAY]: "old" } }, MONDAY, sameTimes.change)).toEqual({
      date_specific_notes: null,
    });
  });

  test("skip can't be combined with a change", () => {
    expect(() => changeRecurringOccurrence.parse({ recurring_shift_id: "r", revision: 1, date: MONDAY, skip: true, start: "09:00" })).toThrow();
  });

  test("a new series skips dates where the user already works, including the morning after a night shift", () => {
    const s = series({ first_dates: [MONDAY, WEDNESDAY], ends: { type: "months", value: 1 } });
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

  test("stopping a series ends it after the last date and never makes it longer", () => {
    const s = series({ first_dates: [MONDAY], ends: { type: "months", value: 2 } });
    const end = stoppedEnd(s, addDays(MONDAY, 7));
    expect(seriesDates({ ...s, end_condition: end }, MONDAY, addDays(MONDAY, 60))).toEqual([MONDAY, addDays(MONDAY, 7)]);
    expect(() => stoppedEnd(s, addDays(MONDAY, 200))).toThrow("already ends");
    expect(() => stoppedEnd(s, addDays(MONDAY, -1))).toThrow("delete_recurring_shift");
  });

  test("a new start keeps the shift's length, and ends: never removes the end", () => {
    const s = { ...series({ first_dates: [MONDAY], start: "22:00", end: "06:00", ends: { type: "years", value: 1 } }), end_time: "06:00:00+00" };
    const change = updateRecurringShift.parse({ recurring_shift_id: "r", revision: 1, start: "18:00", ends: { type: "never" } });
    expect(seriesUpdate(s, change)).toEqual({ set: { start_time: "18:00", end_time: "02:00" }, clear: ["end_condition"] });
  });

  test("adding the same series again is recognised, whatever the stored time format or weekday order", () => {
    const added = series({ first_dates: [MONDAY, WEDNESDAY], start: "16:00", end: "24:00", ends: { type: "months", value: 3 } });
    const stored = {
      ...series({ first_dates: [WEDNESDAY, MONDAY], start: "16:00", end: "00:00", ends: { type: "months", value: 3 } }),
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
  test("an all-day reminder without a reminder time is refused", () => {
    expect(() => addEvent.parse({ note: "Exam", date: MONDAY, reminder_days_before: [1] })).toThrow("reminder_time is required");
  });

  test("all-day reminders are stored as whole days before, largest first, with the clock time", () => {
    expect(addEvent.parse({ note: " Exam ", date: MONDAY, end_date: WEDNESDAY, reminder_days_before: [0, 2], reminder_time: "09:00" })).toEqual({
      start_date: MONDAY,
      end_date: WEDNESDAY,
      is_all_day: true,
      note: "Exam",
      notification_minutes_array: [2880, 0],
      notification_anchor_time: "09:00",
    });
  });

  test("a timed event can't run past midnight, but may end at 24:00", () => {
    expect(() => addEvent.parse({ note: "Party", date: MONDAY, start: "22:00", end: "02:00" })).toThrow("past midnight");
    expect(addEvent.parse({ note: "Party", date: MONDAY, start: "22:00", end: "24:00", reminder_minutes: [15, 60] })).toMatchObject({
      end_time: "24:00",
      notification_minutes_array: [60, 15],
    });
  });

  test("a timed event refuses all-day reminders", () => {
    expect(() => addEvent.parse({ note: "Call", date: MONDAY, start: "10:00", end: "11:00", reminder_days_before: [1] })).toThrow();
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
  const draft = addPayrollAdjustment.parse({ amount: 1500, description: " Christmas bonus ", category: "bonus", payout_date: MONDAY });

  test("an adjustment on a job whose pay has no tax is paid out as is, in the job's currency", () => {
    expect(adjustmentFields({ ...draft, tax_treatment: "gross_taxable" }, { id: "job", currency: "€", taxEnabled: false })).toEqual({
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
    expect(adjustmentFields(draft, { id: "job", currency: "kr", taxEnabled: true }).tax_treatment).toBe("gross_taxable");
  });

  test("a zero amount, a half earned range and a backwards earned range are refused", () => {
    expect(() => addPayrollAdjustment.parse({ amount: 0, description: "x", payout_date: MONDAY })).toThrow("other than 0");
    expect(() => addPayrollAdjustment.parse({ amount: 1, description: "x", payout_date: MONDAY, earned_from: MONDAY })).toThrow("both");
    expect(() =>
      addPayrollAdjustment.parse({ amount: 1, description: "x", payout_date: MONDAY, earned_from: WEDNESDAY, earned_to: MONDAY }),
    ).toThrow("after earned_to");
  });
});

describe("settings", () => {
  const prev = { shift_reminders_enabled: true, shift_reminder_minutes_array: [60] };

  test("removing every shift reminder time turns shift reminders off", () => {
    const change = updateSettings.parse({ shift_reminder_minutes: [] });
    expect(reminderSettings(prev, change.notification_preferences)).toEqual({ shift_reminders_enabled: false, shift_reminder_minutes_array: [] });
  });

  test("turning shift reminders on without a reminder time is refused", () => {
    const change = updateSettings.parse({ shift_reminders_enabled: true });
    expect(() => reminderSettings({ shift_reminders_enabled: false, shift_reminder_minutes_array: [] }, change.notification_preferences)).toThrow();
  });

  test("settings are routed to the table that stores them, and an unknown time zone is refused", () => {
    expect(updateSettings.parse({ theme: "dark", shared_shifts_enabled: false, schedule_time_zone: "Europe/Oslo" })).toEqual({
      user_settings: { theme: "dark" },
      notification_preferences: { shared_shifts_enabled: false },
      schedule_time_zone: "Europe/Oslo",
    });
    expect(() => updateSettings.parse({ schedule_time_zone: "CET+1" })).toThrow("IANA");
    expect(() => updateSettings.parse({ default_startup_tab: "add" })).toThrow();
  });
});
