import { describe, it, expect } from 'vitest';
import { prepareShiftSnapshots } from '@/lib/payroll/snapshot';
import { PRESET_WAGE_RATES } from '@/lib/payroll/calc';
import { PRESET_SUPPLEMENT_RULES } from '@/lib/payroll/presets';
import type { SupplementRule } from '@/lib/payroll/types';

describe('payroll/snapshot', () => {
  describe('prepareShiftSnapshots', () => {
    describe('wage snapshot resolution', () => {
      it('should capture preset wage based on wage level', () => {
        const settings = {
          use_preset: true,
          current_wage_level: 3,
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(PRESET_WAGE_RATES['3']);
        expect(result.hourly_wage_snapshot).toBe(187.46);
      });

      it('should capture different wage levels correctly', () => {
        for (const level of [1, 2, 3, 4, 5, 6]) {
          const settings = {
            use_preset: true,
            current_wage_level: level,
            custom_wage: null,
            custom_supplements: null,
          };

          const result = prepareShiftSnapshots(settings);
          expect(result.hourly_wage_snapshot).toBe(PRESET_WAGE_RATES[String(level)]);
        }
      });

      it('should capture custom wage when not using preset', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 250.5,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(250.5);
      });

      it('should return null wage when no wage is set', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(null);
      });

      it('should prioritize preset over custom when use_preset is true', () => {
        const settings = {
          use_preset: true,
          current_wage_level: 3,
          custom_wage: 999.99, // Should be ignored
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(PRESET_WAGE_RATES['3']);
        expect(result.hourly_wage_snapshot).not.toBe(999.99);
      });

      it('should return null for invalid wage level', () => {
        const settings = {
          use_preset: true,
          current_wage_level: 999, // Invalid level
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(null);
      });

      it('should ignore custom wage if it is 0', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 0,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(null);
      });

      it('should ignore custom wage if it is negative', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: -100,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(null);
      });
    });

    describe('supplement rules snapshot resolution', () => {
      it('should capture preset supplement rules when using preset', () => {
        const settings = {
          use_preset: true,
          current_wage_level: 3,
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.supplement_rules_snapshot).toEqual({
          rules: PRESET_SUPPLEMENT_RULES,
        });
      });

      it('should capture custom supplement rules when not using preset', () => {
        const customRules: SupplementRule[] = [
          { days: [1, 2, 3, 4, 5], from: '20:00', to: '23:59', rate: 50 },
          { days: [6, 7], from: '00:00', to: '23:59', rate: 100 },
        ];

        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 250,
          custom_supplements: { rules: customRules },
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.supplement_rules_snapshot).toEqual({ rules: customRules });
      });

      it('should return null when no supplement rules are set', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 250,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.supplement_rules_snapshot).toBe(null);
      });

      it('should return null when custom supplements has empty rules array', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 250,
          custom_supplements: { rules: [] },
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.supplement_rules_snapshot).toBe(null);
      });

      it('should prioritize preset rules when use_preset is true', () => {
        const customRules: SupplementRule[] = [
          { days: [1], from: '00:00', to: '23:59', rate: 999 },
        ];

        const settings = {
          use_preset: true,
          current_wage_level: 3,
          custom_wage: null,
          custom_supplements: { rules: customRules }, // Should be ignored
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.supplement_rules_snapshot).toEqual({
          rules: PRESET_SUPPLEMENT_RULES,
        });
        expect(result.supplement_rules_snapshot?.rules).not.toContain(customRules[0]);
      });
    });

    describe('combined scenarios', () => {
      it('should capture both preset wage and preset supplements', () => {
        const settings = {
          use_preset: true,
          current_wage_level: 5,
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(PRESET_WAGE_RATES['5']);
        expect(result.supplement_rules_snapshot).toEqual({
          rules: PRESET_SUPPLEMENT_RULES,
        });
      });

      it('should capture both custom wage and custom supplements', () => {
        const customRules: SupplementRule[] = [
          { days: [1, 2, 3], from: '18:00', to: '22:00', percent: 25 },
        ];

        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 300,
          custom_supplements: { rules: customRules },
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(300);
        expect(result.supplement_rules_snapshot).toEqual({ rules: customRules });
      });

      it('should handle mixed null fields', () => {
        const settings = {
          use_preset: true,
          current_wage_level: 3,
          custom_wage: 250, // Ignored because use_preset is true
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(PRESET_WAGE_RATES['3']);
        expect(result.supplement_rules_snapshot).toEqual({
          rules: PRESET_SUPPLEMENT_RULES,
        });
      });

      it('should return all nulls when settings are empty', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(null);
        expect(result.supplement_rules_snapshot).toBe(null);
      });
    });

    describe('edge cases and validation', () => {
      it('should handle undefined fields gracefully', () => {
        const settings = {};

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(null);
        expect(result.supplement_rules_snapshot).toBe(null);
      });

      it('should handle negative wage levels', () => {
        const settings = {
          use_preset: true,
          current_wage_level: -1, // Special preset
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(PRESET_WAGE_RATES['-1']);
        expect(result.hourly_wage_snapshot).toBe(129.91);
      });

      it('should capture wage level -2', () => {
        const settings = {
          use_preset: true,
          current_wage_level: -2,
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(PRESET_WAGE_RATES['-2']);
        expect(result.hourly_wage_snapshot).toBe(132.90);
      });

      it('should handle decimal custom wages', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 185.75,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(185.75);
      });

      it('should handle very high custom wages', () => {
        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 9999.99,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(9999.99);
      });

      it('should handle supplement rules with both rate and percent', () => {
        const customRules: SupplementRule[] = [
          { days: [1], from: '18:00', to: '22:00', rate: 50, percent: 25 },
        ];

        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 200,
          custom_supplements: { rules: customRules },
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.supplement_rules_snapshot).toEqual({ rules: customRules });
        // Verification that rule is captured as-is (calc.ts will handle priority)
        expect(result.supplement_rules_snapshot?.rules[0].rate).toBe(50);
        expect(result.supplement_rules_snapshot?.rules[0].percent).toBe(25);
      });

      it('should preserve multiple custom supplement rules', () => {
        const customRules: SupplementRule[] = [
          { days: [1, 2, 3, 4, 5], from: '18:00', to: '21:00', rate: 20 },
          { days: [1, 2, 3, 4, 5], from: '21:00', to: '23:59', rate: 40 },
          { days: [6, 7], from: '00:00', to: '23:59', rate: 100 },
        ];

        const settings = {
          use_preset: false,
          current_wage_level: null,
          custom_wage: 200,
          custom_supplements: { rules: customRules },
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.supplement_rules_snapshot?.rules).toHaveLength(3);
        expect(result.supplement_rules_snapshot).toEqual({ rules: customRules });
      });
    });

    describe('realistic scenarios', () => {
      it('should handle apprentice on preset wage level -1', () => {
        const settings = {
          use_preset: true,
          current_wage_level: -1,
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(129.91);
        expect(result.supplement_rules_snapshot?.rules).toEqual(PRESET_SUPPLEMENT_RULES);
      });

      it('should handle senior worker on wage level 6', () => {
        const settings = {
          use_preset: true,
          current_wage_level: 6,
          custom_wage: null,
          custom_supplements: null,
        };

        const result = prepareShiftSnapshots(settings);

        expect(result.hourly_wage_snapshot).toBe(256.14);
        expect(result.supplement_rules_snapshot?.rules).toEqual(PRESET_SUPPLEMENT_RULES);
      });

      it('should handle worker switching from preset to custom', () => {
        // Worker starts with preset
        const presetSettings = {
          use_preset: true,
          current_wage_level: 3,
          custom_wage: null,
          custom_supplements: null,
        };

        const presetResult = prepareShiftSnapshots(presetSettings);
        expect(presetResult.hourly_wage_snapshot).toBe(PRESET_WAGE_RATES['3']);

        // Worker negotiates custom wage
        const customSettings = {
          use_preset: false,
          current_wage_level: 3, // Still set but ignored
          custom_wage: 220,
          custom_supplements: { rules: [] },
        };

        const customResult = prepareShiftSnapshots(customSettings);
        expect(customResult.hourly_wage_snapshot).toBe(220);
        expect(customResult.supplement_rules_snapshot).toBe(null); // Empty rules
      });
    });
  });
});
