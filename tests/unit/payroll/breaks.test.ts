import { describe, it, expect } from 'vitest';
import { applyBreakDeduction } from '@/lib/payroll/breaks';
import type { WagePeriod, BreakMethod } from '@/lib/payroll/types';

describe('payroll/breaks', () => {
  const createPeriod = (
    fromMin: number,
    toMin: number,
    baseRate: number = 200,
    supplementRate: number = 0
  ): WagePeriod => ({
    fromMin,
    toMin,
    baseRate,
    supplementRate,
    totalRate: baseRate + supplementRate,
  });

  describe('applyBreakDeduction', () => {
    describe('threshold behavior', () => {
      it('should deduct break when shift exceeds threshold', () => {
        const periods = [createPeriod(0, 480)]; // 8 hours
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.5);

        expect(result.audit.deductedHours).toBe(0.5);
        const totalMinutes = result.periods.reduce(
          (sum, p) => sum + (p.toMin - p.fromMin),
          0
        );
        expect(totalMinutes).toBe(450); // 480 - 30
      });

      it('should not deduct break when shift is below threshold', () => {
        const periods = [createPeriod(0, 300)]; // 5 hours
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.5);

        expect(result.audit.deductedHours).toBe(0);
        const totalMinutes = result.periods.reduce(
          (sum, p) => sum + (p.toMin - p.fromMin),
          0
        );
        expect(totalMinutes).toBe(300); // No deduction
      });

      it('should not deduct break when method is "none"', () => {
        const periods = [createPeriod(0, 480)]; // 8 hours
        const result = applyBreakDeduction(periods, 'none', 5.5, 0.5);

        // Note: audit.deductedHours reflects what WOULD be deducted if method wasn't "none"
        // The periods themselves are not modified
        const totalMinutes = result.periods.reduce(
          (sum, p) => sum + (p.toMin - p.fromMin),
          0
        );
        expect(totalMinutes).toBe(480); // No deduction
        expect(result.periods[0].toMin).toBe(480); // Period unchanged
      });
    });

    describe('proportional method', () => {
      it('should deduct proportionally across single period', () => {
        const periods = [createPeriod(0, 480)]; // 8 hours
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.5);

        expect(result.periods).toHaveLength(1);
        expect(result.periods[0].toMin - result.periods[0].fromMin).toBe(450); // 480 - 30
        expect(result.audit.notes).toContain('Deducted proportionally across periods');
      });

      it('should deduct proportionally across multiple periods', () => {
        const periods = [
          createPeriod(0, 240), // 4 hours (50%)
          createPeriod(240, 480), // 4 hours (50%)
        ];
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.5);

        expect(result.periods).toHaveLength(2);
        // Each period should have 15 minutes deducted (50% of 30 minutes)
        expect(result.periods[0].toMin - result.periods[0].fromMin).toBeCloseTo(225, 0);
        expect(result.periods[1].toMin - result.periods[1].fromMin).toBeCloseTo(225, 0);
      });

      it('should deduct proportionally with uneven periods', () => {
        const periods = [
          createPeriod(0, 120), // 2 hours (25%)
          createPeriod(120, 480), // 6 hours (75%)
        ];
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.5);

        expect(result.periods).toHaveLength(2);
        const total = result.periods.reduce(
          (sum, p) => sum + (p.toMin - p.fromMin),
          0
        );
        expect(total).toBeCloseTo(450, 0); // 480 - 30
      });
    });

    describe('end_of_shift method', () => {
      it('should deduct from end of single period', () => {
        const periods = [createPeriod(0, 480)]; // 8 hours
        const result = applyBreakDeduction(periods, 'end_of_shift', 5.5, 0.5);

        expect(result.periods).toHaveLength(1);
        expect(result.periods[0].fromMin).toBe(0);
        expect(result.periods[0].toMin).toBe(450); // 480 - 30
        expect(result.audit.notes).toContain('Deducted at end of shift');
      });

      it('should deduct from last period first', () => {
        const periods = [
          createPeriod(0, 240, 200, 0), // 4 hours base
          createPeriod(240, 480, 200, 50), // 4 hours with supplement
        ];
        const result = applyBreakDeduction(periods, 'end_of_shift', 5.5, 0.5);

        expect(result.periods).toHaveLength(2);
        expect(result.periods[0].toMin - result.periods[0].fromMin).toBe(240); // Unchanged
        expect(result.periods[1].toMin - result.periods[1].fromMin).toBe(210); // 240 - 30
      });

      it('should remove period entirely if break exceeds its duration', () => {
        const periods = [
          createPeriod(0, 240), // 4 hours
          createPeriod(240, 260), // 20 minutes
        ];
        const result = applyBreakDeduction(periods, 'end_of_shift', 3, 0.5);

        expect(result.periods).toHaveLength(1);
        expect(result.periods[0].toMin - result.periods[0].fromMin).toBe(230); // 260 - 30
      });
    });

    describe('base_only method', () => {
      it('should deduct from base periods first', () => {
        const periods = [
          createPeriod(0, 240, 200, 0), // 4 hours base (no supplement)
          createPeriod(240, 480, 200, 50), // 4 hours with supplement
        ];
        const result = applyBreakDeduction(periods, 'base_only', 5.5, 0.5);

        expect(result.periods).toHaveLength(2);
        expect(result.periods[0].toMin - result.periods[0].fromMin).toBe(210); // Deducted
        expect(result.periods[1].toMin - result.periods[1].fromMin).toBe(240); // Unchanged
        expect(result.audit.notes).toContain('Deducted from base/lowest supplement periods first');
      });

      it('should sort by supplement rate and deduct from lowest first', () => {
        const periods = [
          createPeriod(0, 120, 200, 100), // 2 hours, 100 supplement
          createPeriod(120, 240, 200, 0), // 2 hours, 0 supplement (lowest)
          createPeriod(240, 480, 200, 50), // 4 hours, 50 supplement
        ];
        const result = applyBreakDeduction(periods, 'base_only', 5.5, 0.5);

        // Should deduct 30 minutes from the period with 0 supplement
        const period2 = result.periods.find(p => p.fromMin === 120);
        expect(period2).toBeDefined();
        expect(period2!.toMin - period2!.fromMin).toBe(90); // 120 - 30
      });

      it('should deduct from multiple periods if break exceeds first period', () => {
        const periods = [
          createPeriod(0, 120, 200, 0), // 2 hours base (lowest supplement)
          createPeriod(120, 240, 200, 25), // 2 hours with small supplement
          createPeriod(240, 480, 200, 50), // 4 hours with higher supplement
        ];
        const result = applyBreakDeduction(periods, 'base_only', 5.5, 3); // 3 hour break

        // Should remove first period (2h) and deduct 1h from second
        expect(result.periods).toHaveLength(2);
      });
    });

    describe('edge cases', () => {
      it('should handle empty periods array', () => {
        const periods: WagePeriod[] = [];
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.5);

        expect(result.periods).toHaveLength(0);
        expect(result.audit.deductedHours).toBe(0);
      });

      it('should handle break larger than shift duration', () => {
        const periods = [createPeriod(0, 120)]; // 2 hours
        const result = applyBreakDeduction(periods, 'end_of_shift', 1, 3); // 3 hour break

        expect(result.periods).toHaveLength(0); // All time deducted
      });

      it('should handle zero break deduction', () => {
        const periods = [createPeriod(0, 480)];
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0);

        expect(result.periods).toHaveLength(1);
        expect(result.periods[0].toMin - result.periods[0].fromMin).toBe(480);
        expect(result.audit.deductedHours).toBe(0);
      });

      it('should handle very small break deduction', () => {
        const periods = [createPeriod(0, 480)]; // 8 hours
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.01); // 0.6 minutes

        expect(result.periods).toHaveLength(1);
        const totalMinutes = result.periods[0].toMin - result.periods[0].fromMin;
        expect(totalMinutes).toBeCloseTo(479.4, 1);
      });
    });

    describe('audit trail', () => {
      it('should include correct audit information', () => {
        const periods = [createPeriod(0, 480)];
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.5);

        expect(result.audit.method).toBe('proportional');
        expect(result.audit.thresholdHours).toBe(5.5);
        expect(result.audit.deductedHours).toBe(0.5);
        expect(result.audit.notes).toBeDefined();
        expect(result.audit.notes!.length).toBeGreaterThan(0);
      });

      it('should have empty notes when no deduction occurs', () => {
        const periods = [createPeriod(0, 300)]; // Below threshold
        const result = applyBreakDeduction(periods, 'proportional', 5.5, 0.5);

        expect(result.audit.deductedHours).toBe(0);
        expect(result.audit.notes).toEqual([]);
      });
    });
  });
});
