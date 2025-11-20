/**
 * Property-Based Tests for Date Utilities
 *
 * These tests use fast-check for property-based testing to verify invariants
 * across many random inputs. This is especially important for date/time logic
 * which is prone to edge cases (month boundaries, leap years, DST, etc.)
 */

import { describe, it, expect } from "vitest";
import { fc } from "@fast-check/vitest";
import {
  parseDateAsUTC,
  getCurrentYearMonth,
  getPreviousYearMonth,
  getNextYearMonth,
  getYearMonth,
  isDateInMonth,
  getTodayAsDateString,
  getCurrentYearStart,
  getCurrentYearEnd,
  getMonthStart,
  getMonthEnd,
  getISOWeek,
  formatWeekdayAbbreviation,
  cleanTime,
} from "@/lib/date-utils";

describe("Date Utilities - Property-Based Tests", () => {
  describe("parseDateAsUTC", () => {
    it("should always parse date strings to midnight UTC", () => {
      fc.assert(
        fc.property(
          fc.date({
            min: new Date("2020-01-01"),
            max: new Date("2030-12-31"),
          }),
          (date) => {
            const dateString = date.toISOString().split("T")[0]; // YYYY-MM-DD
            const parsed = parseDateAsUTC(dateString);

            expect(parsed.getUTCHours()).toBe(0);
            expect(parsed.getUTCMinutes()).toBe(0);
            expect(parsed.getUTCSeconds()).toBe(0);
            expect(parsed.getUTCMilliseconds()).toBe(0);
          }
        )
      );
    });

    it("should preserve year, month, and day from input string", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 2020, max: 2030 }),
          fc.integer({ min: 1, max: 12 }),
          fc.integer({ min: 1, max: 28 }), // Safe for all months
          (year, month, day) => {
            const dateString = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
            const parsed = parseDateAsUTC(dateString);

            expect(parsed.getUTCFullYear()).toBe(year);
            expect(parsed.getUTCMonth() + 1).toBe(month);
            expect(parsed.getUTCDate()).toBe(day);
          }
        )
      );
    });
  });

  describe("getYearMonth", () => {
    it("should extract correct year and month from any date", () => {
      fc.assert(
        fc.property(
          fc.date({
            min: new Date("2020-01-01"),
            max: new Date("2030-12-31"),
          }),
          (date) => {
            const { year, month } = getYearMonth(date);

            expect(year).toBe(date.getUTCFullYear());
            expect(month).toBe(date.getUTCMonth() + 1);
            expect(month).toBeGreaterThanOrEqual(1);
            expect(month).toBeLessThanOrEqual(12);
          }
        )
      );
    });
  });

  describe("isDateInMonth", () => {
    it("should correctly identify dates within the same month", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 2020, max: 2030 }),
          fc.integer({ min: 1, max: 12 }),
          fc.integer({ min: 1, max: 28 }), // Safe for all months
          (year, month, day) => {
            const dateString = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;

            expect(isDateInMonth(dateString, year, month)).toBe(true);
          }
        )
      );
    });

    it("should reject dates from different months", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 2020, max: 2030 }),
          fc.integer({ min: 1, max: 12 }),
          fc.integer({ min: 1, max: 28 }),
          (year, month, day) => {
            const dateString = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
            const differentMonth = month === 12 ? 1 : month + 1;

            expect(isDateInMonth(dateString, year, differentMonth)).toBe(false);
          }
        )
      );
    });
  });

  describe("getMonthStart and getMonthEnd", () => {
    it("should always return valid date strings", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 2020, max: 2030 }),
          fc.integer({ min: 1, max: 12 }),
          (year, month) => {
            const start = getMonthStart(year, month);
            const end = getMonthEnd(year, month);

            // Should match YYYY-MM-DD format
            expect(start).toMatch(/^\d{4}-\d{2}-\d{2}$/);
            expect(end).toMatch(/^\d{4}-\d{2}-\d{2}$/);

            // Start should always be the 1st
            expect(start.endsWith("-01")).toBe(true);

            // Parse and verify
            const startDate = parseDateAsUTC(start);
            const endDate = parseDateAsUTC(end);

            expect(startDate.getUTCFullYear()).toBe(year);
            expect(startDate.getUTCMonth() + 1).toBe(month);
            expect(startDate.getUTCDate()).toBe(1);

            expect(endDate.getUTCFullYear()).toBe(year);
            expect(endDate.getUTCMonth() + 1).toBe(month);

            // End date should be after start date
            expect(endDate.getTime()).toBeGreaterThan(startDate.getTime());
          }
        )
      );
    });

    it("should handle month boundaries correctly (including leap years)", () => {
      // February in leap year (2024)
      expect(getMonthEnd(2024, 2)).toBe("2024-02-29");

      // February in non-leap year (2025)
      expect(getMonthEnd(2025, 2)).toBe("2025-02-28");

      // 30-day months
      expect(getMonthEnd(2025, 4)).toBe("2025-04-30");
      expect(getMonthEnd(2025, 6)).toBe("2025-06-30");
      expect(getMonthEnd(2025, 9)).toBe("2025-09-30");
      expect(getMonthEnd(2025, 11)).toBe("2025-11-30");

      // 31-day months
      expect(getMonthEnd(2025, 1)).toBe("2025-01-31");
      expect(getMonthEnd(2025, 3)).toBe("2025-03-31");
      expect(getMonthEnd(2025, 5)).toBe("2025-05-31");
      expect(getMonthEnd(2025, 7)).toBe("2025-07-31");
      expect(getMonthEnd(2025, 8)).toBe("2025-08-31");
      expect(getMonthEnd(2025, 10)).toBe("2025-10-31");
      expect(getMonthEnd(2025, 12)).toBe("2025-12-31");
    });

    it("should cover entire month range (start to end)", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 2020, max: 2030 }),
          fc.integer({ min: 1, max: 12 }),
          fc.integer({ min: 1, max: 28 }), // Safe for all months
          (year, month, day) => {
            const start = getMonthStart(year, month);
            const end = getMonthEnd(year, month);
            const dateString = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;

            const startDate = parseDateAsUTC(start);
            const endDate = parseDateAsUTC(end);
            const testDate = parseDateAsUTC(dateString);

            // Any date in the month should be between start and end (inclusive)
            expect(testDate.getTime()).toBeGreaterThanOrEqual(
              startDate.getTime()
            );
            expect(testDate.getTime()).toBeLessThanOrEqual(endDate.getTime());
          }
        )
      );
    });
  });

  describe("getPreviousYearMonth and getNextYearMonth", () => {
    it("should return valid year/month objects", () => {
      const previous = getPreviousYearMonth();
      const next = getNextYearMonth();
      const current = getCurrentYearMonth();

      // All should have valid year and month
      expect(previous.year).toBeGreaterThan(2020);
      expect(previous.month).toBeGreaterThanOrEqual(1);
      expect(previous.month).toBeLessThanOrEqual(12);

      expect(next.year).toBeGreaterThan(2020);
      expect(next.month).toBeGreaterThanOrEqual(1);
      expect(next.month).toBeLessThanOrEqual(12);

      // Previous should be before current, next should be after
      const prevDate = new Date(Date.UTC(previous.year, previous.month - 1, 1));
      const currDate = new Date(Date.UTC(current.year, current.month - 1, 1));
      const nextDate = new Date(Date.UTC(next.year, next.month - 1, 1));

      expect(prevDate.getTime()).toBeLessThan(currDate.getTime());
      expect(nextDate.getTime()).toBeGreaterThan(currDate.getTime());
    });

    it("should handle year wraparound logic (manual verification)", () => {
      // When current month is January, previous should be December of previous year
      // When current month is December, next should be January of next year
      // These are tested implicitly by the date comparison above

      const current = getCurrentYearMonth();
      const previous = getPreviousYearMonth();
      const next = getNextYearMonth();

      if (current.month === 1) {
        // January - previous should be December of last year
        expect(previous.month).toBe(12);
        expect(previous.year).toBe(current.year - 1);
      } else {
        // Other months - previous should be same year (or Dec of last year if Jan)
        expect(previous.month).toBe(current.month - 1);
      }

      if (current.month === 12) {
        // December - next should be January of next year
        expect(next.month).toBe(1);
        expect(next.year).toBe(current.year + 1);
      } else {
        // Other months - next should be same year
        expect(next.month).toBe(current.month + 1);
      }
    });
  });

  describe("getCurrentYearStart and getCurrentYearEnd", () => {
    it("should return correct year boundaries", () => {
      const start = getCurrentYearStart();
      const end = getCurrentYearEnd();

      const now = new Date();
      const currentYear = now.getUTCFullYear();

      expect(start).toBe(`${currentYear}-01-01`);
      expect(end).toBe(`${currentYear}-12-31`);

      // Verify they parse correctly
      const startDate = parseDateAsUTC(start);
      const endDate = parseDateAsUTC(end);

      expect(startDate.getUTCFullYear()).toBe(currentYear);
      expect(startDate.getUTCMonth()).toBe(0); // January
      expect(startDate.getUTCDate()).toBe(1);

      expect(endDate.getUTCFullYear()).toBe(currentYear);
      expect(endDate.getUTCMonth()).toBe(11); // December
      expect(endDate.getUTCDate()).toBe(31);
    });
  });

  describe("getISOWeek", () => {
    it("should return week numbers in valid range (1-53)", () => {
      fc.assert(
        fc.property(
          fc.date({
            min: new Date("2020-01-01"),
            max: new Date("2030-12-31"),
          }),
          (date) => {
            const week = getISOWeek(date);

            expect(week).toBeGreaterThanOrEqual(1);
            expect(week).toBeLessThanOrEqual(53);
          }
        )
      );
    });

    it("should be consistent for dates in the same week", () => {
      // ISO weeks start on Monday
      const monday = new Date("2025-01-06T00:00:00Z"); // A Monday
      const tuesday = new Date("2025-01-07T00:00:00Z");
      const sunday = new Date("2025-01-12T00:00:00Z"); // Following Sunday

      const weekMonday = getISOWeek(monday);
      const weekTuesday = getISOWeek(tuesday);
      const weekSunday = getISOWeek(sunday);

      expect(weekMonday).toBe(weekTuesday);
      expect(weekMonday).toBe(weekSunday);
    });

    it("should handle known week numbers correctly", () => {
      // 2025-01-01 is a Wednesday, which belongs to week 1 of 2025
      expect(getISOWeek(new Date("2025-01-01T00:00:00Z"))).toBe(1);

      // 2024-01-01 is a Monday, which is week 1 of 2024
      expect(getISOWeek(new Date("2024-01-01T00:00:00Z"))).toBe(1);
    });
  });

  describe("formatWeekdayAbbreviation", () => {
    it("should return 2-character strings for all weekdays", () => {
      fc.assert(
        fc.property(
          fc.date({
            min: new Date("2020-01-01"),
            max: new Date("2030-12-31"),
          }),
          fc.constantFrom("en", "no"),
          (date, locale) => {
            const abbr = formatWeekdayAbbreviation(date, locale);

            expect(abbr).toHaveLength(2);
            expect(abbr).toMatch(/^[A-ZÆØÅ]{2}$/);
          }
        )
      );
    });

    it("should return consistent abbreviations for the same weekday", () => {
      // All Mondays should have the same abbreviation
      const monday1 = new Date("2025-01-06"); // Monday
      const monday2 = new Date("2025-01-13"); // Monday
      const monday3 = new Date("2025-01-20"); // Monday

      const enAbbr1 = formatWeekdayAbbreviation(monday1, "en");
      const enAbbr2 = formatWeekdayAbbreviation(monday2, "en");
      const enAbbr3 = formatWeekdayAbbreviation(monday3, "en");

      expect(enAbbr1).toBe(enAbbr2);
      expect(enAbbr2).toBe(enAbbr3);

      const noAbbr1 = formatWeekdayAbbreviation(monday1, "no");
      const noAbbr2 = formatWeekdayAbbreviation(monday2, "no");
      const noAbbr3 = formatWeekdayAbbreviation(monday3, "no");

      expect(noAbbr1).toBe(noAbbr2);
      expect(noAbbr2).toBe(noAbbr3);
    });
  });

  describe("cleanTime", () => {
    it("should always return HH:MM format or empty for valid inputs", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 0, max: 23 }),
          fc.integer({ min: 0, max: 59 }),
          (hours, minutes) => {
            const hh = String(hours).padStart(2, "0");
            const mm = String(minutes).padStart(2, "0");

            // Test various input formats
            const formats = [
              `${hh}:${mm}`,
              `${hh}:${mm}:00`,
              `${hh}:${mm}:00+01:00`,
              `${hh}:${mm}:00-05:00`,
              `${hh}:${mm}+02:00`,
            ];

            formats.forEach((input) => {
              const cleaned = cleanTime(input);

              expect(cleaned).toBe(`${hh}:${mm}`);
              expect(cleaned).toMatch(/^\d{2}:\d{2}$/);
            });
          }
        )
      );
    });

    it("should handle timezone offsets correctly", () => {
      expect(cleanTime("12:30:00+01:00")).toBe("12:30");
      expect(cleanTime("12:30:00-05:00")).toBe("12:30");
      expect(cleanTime("23:59:59+00:00")).toBe("23:59");
      expect(cleanTime("00:00:00-12:00")).toBe("00:00");
    });

    it("should handle time without seconds or timezone", () => {
      expect(cleanTime("12:30")).toBe("12:30");
      expect(cleanTime("00:00")).toBe("00:00");
      expect(cleanTime("23:59")).toBe("23:59");
    });

    it("should handle empty or invalid input gracefully", () => {
      expect(cleanTime("")).toBe("");
      expect(cleanTime("12:30:00")).toBe("12:30");
    });

    it("should be idempotent (cleaning twice gives same result)", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 0, max: 23 }),
          fc.integer({ min: 0, max: 59 }),
          (hours, minutes) => {
            const hh = String(hours).padStart(2, "0");
            const mm = String(minutes).padStart(2, "0");
            const input = `${hh}:${mm}:00+01:00`;

            const cleaned1 = cleanTime(input);
            const cleaned2 = cleanTime(cleaned1);

            expect(cleaned1).toBe(cleaned2);
          }
        )
      );
    });
  });

  describe("getTodayAsDateString", () => {
    it("should return valid YYYY-MM-DD format", () => {
      const today = getTodayAsDateString();

      expect(today).toMatch(/^\d{4}-\d{2}-\d{2}$/);

      // Should parse without errors
      const parsed = parseDateAsUTC(today);
      expect(parsed).toBeInstanceOf(Date);
      expect(parsed.getTime()).not.toBeNaN();
    });

    it("should be parseable and match current UTC date", () => {
      const today = getTodayAsDateString();
      const parsed = parseDateAsUTC(today);
      const now = new Date();

      expect(parsed.getUTCFullYear()).toBe(now.getUTCFullYear());
      expect(parsed.getUTCMonth()).toBe(now.getUTCMonth());
      expect(parsed.getUTCDate()).toBe(now.getUTCDate());
    });
  });

  describe("Date Parsing Reversibility", () => {
    it("should be reversible (parse → format → parse)", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 2020, max: 2030 }),
          fc.integer({ min: 1, max: 12 }),
          fc.integer({ min: 1, max: 28 }),
          (year, month, day) => {
            const dateString = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
            const parsed = parseDateAsUTC(dateString);

            // Format it back
            const formatted = `${parsed.getUTCFullYear()}-${String(parsed.getUTCMonth() + 1).padStart(2, "0")}-${String(parsed.getUTCDate()).padStart(2, "0")}`;

            expect(formatted).toBe(dateString);

            // Parse again
            const reParsed = parseDateAsUTC(formatted);
            expect(reParsed.getTime()).toBe(parsed.getTime());
          }
        )
      );
    });
  });

  describe("Month Iteration Coverage", () => {
    it("should iterate over all dates in a month range", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 2020, max: 2030 }),
          fc.integer({ min: 1, max: 12 }),
          (year, month) => {
            const start = getMonthStart(year, month);
            const end = getMonthEnd(year, month);

            const startDate = parseDateAsUTC(start);
            const endDate = parseDateAsUTC(end);

            const dates: string[] = [];
            let current = new Date(startDate);

            while (current <= endDate) {
              const dateStr = `${current.getUTCFullYear()}-${String(current.getUTCMonth() + 1).padStart(2, "0")}-${String(current.getUTCDate()).padStart(2, "0")}`;
              dates.push(dateStr);
              current.setUTCDate(current.getUTCDate() + 1);
            }

            // All dates should be in the same month
            dates.forEach((dateStr) => {
              expect(isDateInMonth(dateStr, year, month)).toBe(true);
            });

            // Should have correct number of days
            const daysInMonth = endDate.getUTCDate();
            expect(dates).toHaveLength(daysInMonth);
          }
        )
      );
    });
  });
});
