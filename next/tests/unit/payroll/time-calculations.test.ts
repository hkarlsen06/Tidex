/**
 * Property-Based Tests for Time Calculations
 *
 * Tests cross-midnight shifts, duration calculations, and time range invariants.
 * Focus on synchronous logic testing for reliability.
 */

import { describe, it, expect } from "vitest";
import { fc } from "@fast-check/vitest";
import { crossesMidnight } from "@/lib/payroll/effect";
import type { ShiftRow } from "@/lib/payroll/types";

describe("Time Calculations - Property-Based Tests", () => {
  const timeArbitrary = fc
    .tuple(
      fc.integer({ min: 0, max: 23 }),
      fc.integer({ min: 0, max: 59 })
    )
    .map(
      ([h, m]) =>
        `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`
    );

  const shiftRowArbitrary = fc.record({
    id: fc.uuid(),
    user_id: fc.uuid(),
    shift_date: fc
      .date({ min: new Date("2024-01-01"), max: new Date("2025-12-31") })
      .filter((d) => !isNaN(d.getTime()))
      .map((d) => d.toISOString().split("T")[0]),
    start_time: timeArbitrary,
    end_time: timeArbitrary,
  });

  describe("Cross-Midnight Detection", () => {
    it("should detect cross-midnight when end_time <= start_time", () => {
      fc.assert(
        fc.property(shiftRowArbitrary, (shift) => {
          const isCrossMidnight = crossesMidnight(shift);
          const [startHour, startMin] = shift.start_time.split(":").map(Number);
          const [endHour, endMin] = shift.end_time.split(":").map(Number);

          const startMinutes = startHour * 60 + startMin;
          const endMinutes = endHour * 60 + endMin;

          if (endMinutes <= startMinutes) {
            expect(isCrossMidnight).toBe(true);
          } else {
            expect(isCrossMidnight).toBe(false);
          }
        })
      );
    });

    it("should correctly identify same-day shifts", () => {
      const sameDayShift: ShiftRow = {
        id: "123e4567-e89b-12d3-a456-426614174000",
        user_id: "123e4567-e89b-12d3-a456-426614174001",
        shift_date: "2024-01-15",
        start_time: "09:00",
        end_time: "17:00",
      };

      expect(crossesMidnight(sameDayShift)).toBe(false);
    });

    it("should correctly identify cross-midnight shifts", () => {
      const nightShift: ShiftRow = {
        id: "123e4567-e89b-12d3-a456-426614174000",
        user_id: "123e4567-e89b-12d3-a456-426614174001",
        shift_date: "2024-01-15",
        start_time: "22:00",
        end_time: "06:00",
      };

      expect(crossesMidnight(nightShift)).toBe(true);
    });

    it("should handle edge case: midnight exactly (00:00)", () => {
      // 23:00 to 00:00 is cross-midnight (1 hour)
      expect(
        crossesMidnight({
          id: "123e4567-e89b-12d3-a456-426614174000",
          user_id: "123e4567-e89b-12d3-a456-426614174001",
          shift_date: "2024-01-15",
          start_time: "23:00",
          end_time: "00:00",
        })
      ).toBe(true);

      // 00:00 to 00:00 is cross-midnight (24 hours)
      expect(
        crossesMidnight({
          id: "123e4567-e89b-12d3-a456-426614174000",
          user_id: "123e4567-e89b-12d3-a456-426614174001",
          shift_date: "2024-01-15",
          start_time: "00:00",
          end_time: "00:00",
        })
      ).toBe(true);

      // 00:00 to 08:00 is same-day
      expect(
        crossesMidnight({
          id: "123e4567-e89b-12d3-a456-426614174000",
          user_id: "123e4567-e89b-12d3-a456-426614174001",
          shift_date: "2024-01-15",
          start_time: "00:00",
          end_time: "08:00",
        })
      ).toBe(false);
    });
  });

  describe("Time Format Consistency", () => {
    it("should handle all valid HH:MM combinations", () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 0, max: 23 }),
          fc.integer({ min: 0, max: 59 }),
          fc.integer({ min: 0, max: 23 }),
          fc.integer({ min: 0, max: 59 }),
          (startHour, startMin, endHour, endMin) => {
            const shift: ShiftRow = {
              id: "123e4567-e89b-12d3-a456-426614174000",
              user_id: "123e4567-e89b-12d3-a456-426614174001",
              shift_date: "2024-01-15",
              start_time: `${String(startHour).padStart(2, "0")}:${String(startMin).padStart(2, "0")}`,
              end_time: `${String(endHour).padStart(2, "0")}:${String(endMin).padStart(2, "0")}`,
            };

            const startMinutes = startHour * 60 + startMin;
            const endMinutes = endHour * 60 + endMin;

            const isCrossMidnight = crossesMidnight(shift);
            const expected = endMinutes <= startMinutes;

            expect(isCrossMidnight).toBe(expected);
          }
        )
      );
    });
  });

  describe("Time Range Invariants", () => {
    it("should be deterministic (same input gives same output)", () => {
      fc.assert(
        fc.property(shiftRowArbitrary, (shift) => {
          const result1 = crossesMidnight(shift);
          const result2 = crossesMidnight(shift);

          expect(result1).toBe(result2);
        })
      );
    });

    it("should correctly classify all possible time ranges", () => {
      // Property: For any two times, exactly one of these is true:
      // 1. end > start (same day)
      // 2. end <= start (cross-midnight)
      fc.assert(
        fc.property(
          fc.integer({ min: 0, max: 23 }),
          fc.integer({ min: 0, max: 59 }),
          fc.integer({ min: 0, max: 23 }),
          fc.integer({ min: 0, max: 59 }),
          (h1, m1, h2, m2) => {
            const start = `${String(h1).padStart(2, "0")}:${String(m1).padStart(2, "0")}`;
            const end = `${String(h2).padStart(2, "0")}:${String(m2).padStart(2, "0")}`;

            const shift: ShiftRow = {
              id: "123e4567-e89b-12d3-a456-426614174000",
              user_id: "123e4567-e89b-12d3-a456-426614174001",
              shift_date: "2024-01-15",
              start_time: start,
              end_time: end,
            };

            const isCrossMidnight = crossesMidnight(shift);
            const startMinutes = h1 * 60 + m1;
            const endMinutes = h2 * 60 + m2;

            // Exactly one of these must be true
            if (endMinutes > startMinutes) {
              expect(isCrossMidnight).toBe(false);
            } else {
              expect(isCrossMidnight).toBe(true);
            }
          }
        )
      );
    });
  });

  describe("Known Edge Cases", () => {
    const knownEdgeCases: Array<{
      start: string;
      end: string;
      crossesMidnight: boolean;
      description: string;
    }> = [
      {
        start: "00:00",
        end: "00:00",
        crossesMidnight: true,
        description: "24-hour shift",
      },
      {
        start: "23:59",
        end: "00:01",
        crossesMidnight: true,
        description: "Very short cross-midnight",
      },
      {
        start: "20:00",
        end: "08:00",
        crossesMidnight: true,
        description: "Long night shift",
      },
      {
        start: "09:00",
        end: "17:00",
        crossesMidnight: false,
        description: "Standard day shift",
      },
      {
        start: "00:00",
        end: "08:00",
        crossesMidnight: false,
        description: "Early morning shift",
      },
      {
        start: "16:00",
        end: "23:59",
        crossesMidnight: false,
        description: "Late evening shift",
      },
      {
        start: "12:00",
        end: "12:00",
        crossesMidnight: true,
        description: "24-hour shift starting at noon",
      },
    ];

    knownEdgeCases.forEach(({ start, end, crossesMidnight: expected, description }) => {
      it(`should handle: ${description}`, () => {
        const shift: ShiftRow = {
          id: "123e4567-e89b-12d3-a456-426614174000",
          user_id: "123e4567-e89b-12d3-a456-426614174001",
          shift_date: "2024-01-15",
          start_time: start,
          end_time: end,
        };

        expect(crossesMidnight(shift)).toBe(expected);
      });
    });
  });
});
