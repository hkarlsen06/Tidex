import { describe, it, expect } from 'vitest';
import { buildWagePeriods } from '@/lib/payroll/periods';
import type { SupplementRule } from '@/lib/payroll/types';

describe('payroll/periods', () => {
  describe('buildWagePeriods', () => {
    const baseRate = 200;

    describe('basic period building', () => {
      it('should create single period for shift with no supplements', () => {
        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, []);

        expect(periods).toHaveLength(1);
        expect(periods[0].fromMin).toBe(540); // 9 * 60
        expect(periods[0].toMin).toBe(1020); // 17 * 60
        expect(periods[0].baseRate).toBe(baseRate);
        expect(periods[0].supplementRate).toBe(0);
        expect(periods[0].totalRate).toBe(baseRate);
      });

      it('should split period when supplement applies', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '12:00', to: '14:00', rate: 50 },
        ];

        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, rules);

        expect(periods).toHaveLength(3);
        // Before supplement
        expect(periods[0].fromMin).toBe(540); // 09:00
        expect(periods[0].toMin).toBe(720); // 12:00
        expect(periods[0].supplementRate).toBe(0);

        // During supplement
        expect(periods[1].fromMin).toBe(720); // 12:00
        expect(periods[1].toMin).toBe(840); // 14:00
        expect(periods[1].supplementRate).toBe(50);

        // After supplement
        expect(periods[2].fromMin).toBe(840); // 14:00
        expect(periods[2].toMin).toBe(1020); // 17:00
        expect(periods[2].supplementRate).toBe(0);
      });
    });

    describe('supplement types', () => {
      it('should apply fixed rate supplement', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '18:00', to: '21:00', rate: 45 },
        ];

        const periods = buildWagePeriods('16:00', '20:00', 3, baseRate, rules);

        expect(periods).toHaveLength(2);
        // 16:00-18:00 no supplement
        expect(periods[0].supplementRate).toBe(0);
        // 18:00-20:00 with supplement
        expect(periods[1].supplementRate).toBe(45);
      });

      it('should apply percentage supplement', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '18:00', to: '21:00', percent: 50 },
        ];

        const periods = buildWagePeriods('16:00', '20:00', 3, baseRate, rules);

        expect(periods).toHaveLength(2);
        // 18:00-20:00 with 50% supplement
        expect(periods[1].supplementRate).toBe(100); // 50% of 200
        expect(periods[1].totalRate).toBe(300); // 200 + 100
      });

      it('should prefer rate over percent when both specified', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '18:00', to: '21:00', rate: 45, percent: 50 },
        ];

        const periods = buildWagePeriods('18:00', '20:00', 3, baseRate, rules);

        expect(periods).toHaveLength(1);
        expect(periods[0].supplementRate).toBe(45); // Uses rate, not percent
      });
    });

    describe('overlapping supplements', () => {
      it('should use highest supplement when rules overlap', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '18:00', to: '23:00', rate: 22 },
          { days: [3], from: '21:00', to: '23:59', rate: 45 },
        ];

        const periods = buildWagePeriods('17:00', '23:00', 3, baseRate, rules);

        expect(periods).toHaveLength(3);
        // 17:00-18:00 no supplement
        expect(periods[0].supplementRate).toBe(0);
        // 18:00-21:00 lower supplement
        expect(periods[1].supplementRate).toBe(22);
        // 21:00-23:00 higher supplement wins
        expect(periods[2].supplementRate).toBe(45);
      });

      it('should handle three overlapping supplement levels', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '18:00', to: '23:59', rate: 10 },
          { days: [3], from: '20:00', to: '23:59', rate: 30 },
          { days: [3], from: '22:00', to: '23:59', rate: 50 },
        ];

        const periods = buildWagePeriods('18:00', '23:00', 3, baseRate, rules);

        expect(periods).toHaveLength(3);
        expect(periods[0].supplementRate).toBe(10); // 18:00-20:00
        expect(periods[1].supplementRate).toBe(30); // 20:00-22:00
        expect(periods[2].supplementRate).toBe(50); // 22:00-23:00
      });
    });

    describe('cross-midnight shifts', () => {
      it('should handle shift crossing midnight', () => {
        const periods = buildWagePeriods('22:00', '06:00', 3, baseRate, []);

        expect(periods).toHaveLength(1);
        expect(periods[0].fromMin).toBe(1320); // 22:00 = 22 * 60
        expect(periods[0].toMin).toBe(1800); // 06:00 next day = 30 * 60
        const durationMinutes = periods[0].toMin - periods[0].fromMin;
        expect(durationMinutes).toBe(480); // 8 hours
      });

      it('should apply supplements to cross-midnight shift', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '22:00', to: '23:59', rate: 45 },
          { days: [3], from: '00:00', to: '06:00', rate: 110 },
        ];

        const periods = buildWagePeriods('22:00', '02:00', 3, baseRate, rules);

        // Should split at midnight
        expect(periods.length).toBeGreaterThan(1);
        // First period should have lower supplement
        expect(periods[0].supplementRate).toBe(45);
        // Period after midnight should have higher supplement
        const lastPeriod = periods[periods.length - 1];
        expect(lastPeriod.supplementRate).toBe(110);
      });

      it('should handle cross-midnight supplement rule', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '23:00', to: '01:00', rate: 50 }, // Cross midnight rule
        ];

        const periods = buildWagePeriods('22:00', '02:00', 3, baseRate, rules);

        // Should apply supplement from 23:00 to 01:00
        const supplementPeriod = periods.find(p => p.supplementRate > 0);
        expect(supplementPeriod).toBeDefined();
        expect(supplementPeriod!.supplementRate).toBe(50);
      });
    });

    describe('weekday filtering', () => {
      it('should only apply rules matching weekday', () => {
        const rules: SupplementRule[] = [
          { days: [1, 2, 3, 4, 5], from: '18:00', to: '21:00', rate: 22 }, // Mon-Fri
          { days: [6, 7], from: '00:00', to: '23:59', rate: 115 }, // Sat-Sun
        ];

        // Wednesday (weekday 3) - should get Mon-Fri supplement
        const weekdayPeriods = buildWagePeriods('18:00', '20:00', 3, baseRate, rules);
        expect(weekdayPeriods[0].supplementRate).toBe(22);

        // Saturday (weekday 6) - should get Sat-Sun supplement
        const saturdayPeriods = buildWagePeriods('18:00', '20:00', 6, baseRate, rules);
        expect(saturdayPeriods[0].supplementRate).toBe(115);

        // Sunday (weekday 7) - should get Sat-Sun supplement
        const sundayPeriods = buildWagePeriods('00:00', '08:00', 7, baseRate, rules);
        expect(sundayPeriods[0].supplementRate).toBe(115);
      });

      it('should not apply supplements from other weekdays', () => {
        const rules: SupplementRule[] = [
          { days: [6], from: '00:00', to: '23:59', rate: 115 }, // Only Saturday
        ];

        // Monday - should not get Saturday supplement
        const periods = buildWagePeriods('09:00', '17:00', 1, baseRate, rules);
        expect(periods[0].supplementRate).toBe(0);
      });
    });

    describe('partial overlaps', () => {
      it('should handle supplement starting before shift', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '06:00', to: '12:00', rate: 50 },
        ];

        const periods = buildWagePeriods('09:00', '15:00', 3, baseRate, rules);

        expect(periods).toHaveLength(2);
        // 09:00-12:00 with supplement
        expect(periods[0].supplementRate).toBe(50);
        // 12:00-15:00 no supplement
        expect(periods[1].supplementRate).toBe(0);
      });

      it('should handle supplement ending after shift', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '12:00', to: '20:00', rate: 50 },
        ];

        const periods = buildWagePeriods('09:00', '15:00', 3, baseRate, rules);

        expect(periods).toHaveLength(2);
        // 09:00-12:00 no supplement
        expect(periods[0].supplementRate).toBe(0);
        // 12:00-15:00 with supplement
        expect(periods[1].supplementRate).toBe(50);
      });

      it('should handle supplement fully containing shift', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '06:00', to: '20:00', rate: 50 },
        ];

        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, rules);

        expect(periods).toHaveLength(1);
        expect(periods[0].supplementRate).toBe(50);
      });

      it('should handle shift fully containing supplement', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '12:00', to: '14:00', rate: 50 },
        ];

        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, rules);

        expect(periods).toHaveLength(3);
        expect(periods[0].supplementRate).toBe(0); // 09:00-12:00
        expect(periods[1].supplementRate).toBe(50); // 12:00-14:00
        expect(periods[2].supplementRate).toBe(0); // 14:00-17:00
      });
    });

    describe('edge cases', () => {
      it('should handle zero-length shift', () => {
        const periods = buildWagePeriods('09:00', '09:00', 3, baseRate, []);

        // 09:00 to 09:00 is treated as 24 hours
        expect(periods).toHaveLength(1);
        expect(periods[0].toMin - periods[0].fromMin).toBe(1440); // 24 hours
      });

      it('should handle shift with no matching supplements', () => {
        const rules: SupplementRule[] = [
          { days: [6, 7], from: '00:00', to: '23:59', rate: 115 }, // Weekend only
        ];

        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, rules);

        expect(periods).toHaveLength(1);
        expect(periods[0].supplementRate).toBe(0);
      });

      it('should handle empty rules array', () => {
        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, []);

        expect(periods).toHaveLength(1);
        expect(periods[0].supplementRate).toBe(0);
      });

      it('should handle supplement at exact shift boundaries', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '09:00', to: '17:00', rate: 50 },
        ];

        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, rules);

        expect(periods).toHaveLength(1);
        expect(periods[0].supplementRate).toBe(50);
      });

      it('should handle very short shift (1 minute)', () => {
        const periods = buildWagePeriods('09:00', '09:01', 3, baseRate, []);

        expect(periods).toHaveLength(1);
        expect(periods[0].toMin - periods[0].fromMin).toBe(1);
      });

      it('should handle supplement with rate 0', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '09:00', to: '17:00', rate: 0 },
        ];

        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, rules);

        expect(periods).toHaveLength(1);
        expect(periods[0].supplementRate).toBe(0);
      });

      it('should handle supplement with percent 0', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '09:00', to: '17:00', percent: 0 },
        ];

        const periods = buildWagePeriods('09:00', '17:00', 3, baseRate, rules);

        expect(periods).toHaveLength(1);
        expect(periods[0].supplementRate).toBe(0);
      });
    });

    describe('complex scenarios', () => {
      it('should handle realistic Norwegian tariff rules', () => {
        const rules: SupplementRule[] = [
          { days: [1, 2, 3, 4, 5], from: '18:00', to: '21:00', rate: 22 },
          { days: [1, 2, 3, 4, 5], from: '21:00', to: '23:59', rate: 45 },
          { days: [6], from: '13:00', to: '15:00', rate: 45 },
          { days: [6], from: '15:00', to: '18:00', rate: 55 },
          { days: [6], from: '18:00', to: '23:59', rate: 110 },
          { days: [7], from: '00:00', to: '23:59', rate: 115 },
        ];

        // Friday evening shift
        const fridayPeriods = buildWagePeriods('16:00', '23:00', 5, baseRate, rules);
        expect(fridayPeriods.length).toBeGreaterThan(1);
        const has22Supplement = fridayPeriods.some(p => p.supplementRate === 22);
        const has45Supplement = fridayPeriods.some(p => p.supplementRate === 45);
        expect(has22Supplement).toBe(true);
        expect(has45Supplement).toBe(true);

        // Saturday shift
        const saturdayPeriods = buildWagePeriods('12:00', '20:00', 6, baseRate, rules);
        expect(saturdayPeriods.length).toBeGreaterThan(1);
        const has110Supplement = saturdayPeriods.some(p => p.supplementRate === 110);
        expect(has110Supplement).toBe(true);

        // Sunday all-day shift
        const sundayPeriods = buildWagePeriods('08:00', '16:00', 7, baseRate, rules);
        expect(sundayPeriods).toHaveLength(1);
        expect(sundayPeriods[0].supplementRate).toBe(115);
      });

      it('should handle night shift with multiple supplements', () => {
        const rules: SupplementRule[] = [
          { days: [1, 2, 3, 4, 5], from: '18:00', to: '23:59', rate: 45 },
          { days: [1, 2, 3, 4, 5], from: '00:00', to: '06:00', rate: 110 },
        ];

        const periods = buildWagePeriods('20:00', '04:00', 3, baseRate, rules);

        expect(periods.length).toBeGreaterThan(1);
        // Should have both 45 and 110 supplements in different periods
        const has45 = periods.some(p => p.supplementRate === 45);
        const has110 = periods.some(p => p.supplementRate === 110);
        expect(has45).toBe(true);
        expect(has110).toBe(true);
      });
    });

    describe('minute precision', () => {
      it('should handle odd minute boundaries', () => {
        const rules: SupplementRule[] = [
          { days: [3], from: '09:15', to: '12:45', rate: 50 },
        ];

        const periods = buildWagePeriods('09:00', '13:00', 3, baseRate, rules);

        expect(periods).toHaveLength(3);
        // 09:00-09:15
        expect(periods[0].fromMin).toBe(540);
        expect(periods[0].toMin).toBe(555);
        expect(periods[0].supplementRate).toBe(0);

        // 09:15-12:45
        expect(periods[1].fromMin).toBe(555);
        expect(periods[1].toMin).toBe(765);
        expect(periods[1].supplementRate).toBe(50);

        // 12:45-13:00
        expect(periods[2].fromMin).toBe(765);
        expect(periods[2].toMin).toBe(780);
        expect(periods[2].supplementRate).toBe(0);
      });
    });
  });
});
