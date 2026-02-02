/**
 * Effect-based Payroll Tests
 *
 * Tests for the Effect-wrapped payroll calculation system.
 * These tests validate the Effect layer while the pure calculation
 * logic is tested in calc.test.ts
 */

import { describe, it, expect } from "vitest";
import { Effect } from "effect";
import {
  computeShift,
  computeShifts,
  validateShiftRow,
  validateTimeFormat,
  validateDateFormat,
  calculateDuration,
  crossesMidnight,
} from "@/lib/payroll/effect";
import type { ShiftRow, UserSettings, SupplementRule } from "@/lib/payroll/types";

describe("Effect-based Payroll System", () => {
  const validShift: ShiftRow = {
    id: "123e4567-e89b-12d3-a456-426614174000",
    user_id: "123e4567-e89b-12d3-a456-426614174001",
    shift_date: "2024-01-15",
    start_time: "09:00",
    end_time: "17:00",
  };

  const validSettings: UserSettings = {
    pause_deduction_enabled: true,
    pause_deduction_method: "proportional",
    pause_threshold_hours: 5.5,
    pause_deduction_minutes: 30,
  };

  const validRules: SupplementRule[] = [];

  describe("Validation", () => {
    it("should validate a valid shift", async () => {
      const program = validateShiftRow(validShift);
      const result = await Effect.runPromise(program);

      expect(result).toEqual(validShift);
    });

    it("should reject shift with invalid UUID", async () => {
      const invalidShift = { ...validShift, id: "invalid-uuid" };
      const program = validateShiftRow(invalidShift);

      const result = await Effect.runPromise(Effect.either(program));

      if (result._tag === "Left") {
        expect(result.left._tag).toBe("ValidationError");
        expect(result.left.message).toContain("UUID");
      } else {
        throw new Error("Expected validation to fail");
      }
    });

    it("should reject shift with invalid date format", async () => {
      const invalidShift = { ...validShift, shift_date: "2024/01/15" };
      const program = validateShiftRow(invalidShift);

      const result = await Effect.runPromise(Effect.either(program));

      if (result._tag === "Left") {
        expect(result.left._tag).toBe("ValidationError");
        expect(result.left.message).toContain("YYYY-MM-DD");
      } else {
        throw new Error("Expected validation to fail");
      }
    });

    it("should reject shift with invalid time format", async () => {
      const invalidShift = { ...validShift, start_time: "9:00" }; // Missing leading zero
      const program = validateShiftRow(invalidShift);

      const result = await Effect.runPromise(Effect.either(program));

      if (result._tag === "Left") {
        expect(result.left._tag).toBe("ValidationError");
        expect(result.left.message).toContain("HH:MM");
      } else {
        throw new Error("Expected validation to fail");
      }
    });

    it("should validate time format", async () => {
      const program = validateTimeFormat("14:30");
      const result = await Effect.runPromise(program);

      expect(result).toBe("14:30");
    });

    it("should validate date format", async () => {
      const program = validateDateFormat("2024-01-15");
      const result = await Effect.runPromise(program);

      expect(result).toBe("2024-01-15");
    });
  });

  describe("Computation", () => {
    it("should compute a basic shift", async () => {
      const program = computeShift(validShift, validSettings, validRules);
      const result = await Effect.runPromise(program);

      expect(result.id).toBe(validShift.id);
      expect(result.durationHours).toBeGreaterThan(0);
      expect(result.paidHours).toBeGreaterThan(0);
      expect(result.gross).toBeGreaterThan(0);
      expect(result.basePay).toBeGreaterThan(0);
    });

    it("should handle computation errors gracefully", async () => {
      // Shift with invalid data that passes schema but fails computation
      const problematicShift = {
        ...validShift,
        id: "invalid-uuid" // Will fail UUID validation
      };

      const program = computeShift(
        problematicShift,
        validSettings,
        validRules
      );

      const result = await Effect.runPromise(Effect.either(program));

      expect(result._tag).toBe("Left");
      if (result._tag === "Left") {
        expect(result.left._tag).toBe("ValidationError");
      }
    });
  });

  describe("Parallel Computation", () => {
    it("should compute multiple shifts in parallel", async () => {
      const shifts: ShiftRow[] = [
        validShift,
        {
          ...validShift,
          id: "223e4567-e89b-12d3-a456-426614174000",
          shift_date: "2024-01-16",
        },
        {
          ...validShift,
          id: "323e4567-e89b-12d3-a456-426614174000",
          shift_date: "2024-01-17",
        },
      ];

      const program = computeShifts(shifts, validSettings, validRules);
      const results = await Effect.runPromise(program);

      expect(results).toHaveLength(3);
      results.forEach((result) => {
        expect(result.gross).toBeGreaterThan(0);
      });
    });

    it("should handle partial failures in parallel computation", async () => {
      const shifts: ShiftRow[] = [
        validShift,
        { ...validShift, id: "invalid" }, // Will fail
        {
          ...validShift,
          id: "323e4567-e89b-12d3-a456-426614174000",
        },
      ];

      const program = computeShifts(shifts, validSettings, validRules);
      const result = await Effect.runPromise(Effect.either(program));

      // Should fail on the invalid shift
      expect(result._tag).toBe("Left");
    });
  });

  describe("Duration Calculation", () => {
    it("should calculate duration for normal shifts", async () => {
      const program = calculateDuration(validShift);
      const duration = await Effect.runPromise(program);

      expect(duration).toBe(8); // 9:00 to 17:00 = 8 hours
    });

    it("should calculate duration for cross-midnight shifts", async () => {
      const nightShift: ShiftRow = {
        ...validShift,
        start_time: "22:00",
        end_time: "06:00",
      };

      const program = calculateDuration(nightShift);
      const duration = await Effect.runPromise(program);

      expect(duration).toBe(8); // 22:00 to 06:00 = 8 hours
    });

    it("should detect cross-midnight shifts", () => {
      const nightShift: ShiftRow = {
        ...validShift,
        start_time: "22:00",
        end_time: "06:00",
      };

      expect(crossesMidnight(nightShift)).toBe(true);
      expect(crossesMidnight(validShift)).toBe(false);
    });
  });

  describe("Property-Based Invariants", () => {
    it("paid hours should never exceed duration hours", async () => {
      const program = computeShift(validShift, validSettings, validRules);
      const result = await Effect.runPromise(program);

      expect(result.paidHours).toBeLessThanOrEqual(result.durationHours);
    });

    it("gross pay should equal base pay + supplement pay", async () => {
      const program = computeShift(validShift, validSettings, validRules);
      const result = await Effect.runPromise(program);

      const expected = +(result.basePay + result.supplementPay).toFixed(2);
      expect(result.gross).toBe(expected);
    });

    it("break deduction should be reasonable", async () => {
      const program = computeShift(validShift, validSettings, validRules);
      const result = await Effect.runPromise(program);

      const breakHours = result.durationHours - result.paidHours;

      // Break should be non-negative
      expect(breakHours).toBeGreaterThanOrEqual(0);

      // Break should not exceed the shift duration
      expect(breakHours).toBeLessThan(result.durationHours);
    });
  });
});
