import { NextResponse } from 'next/server';
import {
  computeShift,
  PRESET_SUPPLEMENT_RULES,
  PRESET_WAGE_RATES,
  prepareShiftSnapshots,
  type ShiftRow,
  type UserSettings,
} from '@/lib/payroll';

export async function GET() {
  // Test 1: Verify snapshot preparation
  const settingsPreset: UserSettings = {
    use_preset: true,
    current_wage_level: 3,
    custom_supplements: null,
  };

  const settingsCustom: UserSettings = {
    use_preset: false,
    custom_wage: 250,
    custom_supplements: {
      rules: [
        { days: [1, 2, 3, 4, 5], from: "17:00", to: "22:00", rate: 50 },
      ],
    },
  };

  const snapshotsPreset = prepareShiftSnapshots(settingsPreset);
  const snapshotsCustom = prepareShiftSnapshots(settingsCustom);

  // Test 2: Shift WITHOUT snapshots (should use current settings)
  const shiftWithoutSnapshot: ShiftRow = {
    id: "test-no-snapshot",
    shift_date: "2024-10-02", // Thursday (day 4)
    start_time: "18:00",
    end_time: "22:00",
    hourly_wage_snapshot: null,
    supplement_rules_snapshot: null,
    user_id: "test",
  };

  const currentSettings: UserSettings = {
    use_preset: true,
    current_wage_level: 3, // 187.46 NOK
    pause_deduction_enabled: false,
  };

  const resultWithoutSnapshot = computeShift(
    shiftWithoutSnapshot,
    currentSettings,
    PRESET_SUPPLEMENT_RULES
  );

  // Test 3: Shift WITH snapshots (should override current settings)
  const shiftWithSnapshot: ShiftRow = {
    id: "test-with-snapshot",
    shift_date: "2024-10-02", // Thursday (day 4)
    start_time: "18:00",
    end_time: "22:00",
    hourly_wage_snapshot: 200.0, // Different from current level 3 (187.46)
    supplement_rules_snapshot: {
      rules: [
        // Custom historical supplement (different from preset)
        { days: [1, 2, 3, 4, 5], from: "17:00", to: "23:00", rate: 30 },
      ],
    },
    user_id: "test",
  };

  const resultWithSnapshot = computeShift(
    shiftWithSnapshot,
    currentSettings, // Even though settings say level 3, snapshot should override
    PRESET_SUPPLEMENT_RULES // Even though presets are passed, snapshot should override
  );

  // Test 4: Verify wage snapshot works
  const shiftWageSnapshotOnly: ShiftRow = {
    id: "test-wage-snapshot",
    shift_date: "2024-10-02",
    start_time: "18:00",
    end_time: "22:00",
    hourly_wage_snapshot: 300.0, // High wage to make it obvious
    supplement_rules_snapshot: null, // No supplement snapshot, should use current
    user_id: "test",
  };

  const resultWageSnapshotOnly = computeShift(
    shiftWageSnapshotOnly,
    currentSettings,
    PRESET_SUPPLEMENT_RULES
  );

  // Test 5: Verify supplement snapshot works
  const shiftSupplementSnapshotOnly: ShiftRow = {
    id: "test-supplement-snapshot",
    shift_date: "2024-10-02",
    start_time: "18:00",
    end_time: "22:00",
    hourly_wage_snapshot: null, // No wage snapshot, should use current (187.46)
    supplement_rules_snapshot: {
      rules: [
        { days: [1, 2, 3, 4, 5], from: "18:00", to: "20:00", rate: 100 }, // Very high supplement
      ],
    },
    user_id: "test",
  };

  const resultSupplementSnapshotOnly = computeShift(
    shiftSupplementSnapshotOnly,
    currentSettings,
    PRESET_SUPPLEMENT_RULES
  );

  return NextResponse.json({
    tests: {
      test1_snapshot_preparation: {
        description: "Verify prepareShiftSnapshots() captures correct values",
        preset: {
          input: settingsPreset,
          output: snapshotsPreset,
          expected: {
            hourly_wage_snapshot: PRESET_WAGE_RATES["3"], // 187.46
            supplement_rules_snapshot: { rules: PRESET_SUPPLEMENT_RULES },
          },
          pass:
            snapshotsPreset.hourly_wage_snapshot === PRESET_WAGE_RATES["3"] &&
            snapshotsPreset.supplement_rules_snapshot?.rules?.length ===
              PRESET_SUPPLEMENT_RULES.length,
        },
        custom: {
          input: settingsCustom,
          output: snapshotsCustom,
          expected: {
            hourly_wage_snapshot: 250,
            supplement_rules_snapshot: {
              rules: [{ days: [1, 2, 3, 4, 5], from: "17:00", to: "22:00", rate: 50 }],
            },
          },
          pass:
            snapshotsCustom.hourly_wage_snapshot === 250 &&
            snapshotsCustom.supplement_rules_snapshot?.rules?.length === 1,
        },
      },

      test2_without_snapshots: {
        description:
          "Shift without snapshots should use current settings (level 3: 187.46 NOK)",
        shift: shiftWithoutSnapshot,
        currentSettings,
        result: {
          basePay: resultWithoutSnapshot.basePay,
          supplementPay: resultWithoutSnapshot.supplementPay,
          gross: resultWithoutSnapshot.gross,
          wagePeriods: resultWithoutSnapshot.wagePeriods,
        },
        verification: {
          baseRateUsed:
            resultWithoutSnapshot.wagePeriods[0]?.baseRate === PRESET_WAGE_RATES["3"],
          supplementsUsed: resultWithoutSnapshot.wagePeriods.some(
            (p) => p.supplementRate > 0
          ),
        },
      },

      test3_with_both_snapshots: {
        description:
          "Shift with both snapshots should override current settings (200 NOK, custom supplement)",
        shift: shiftWithSnapshot,
        currentSettings,
        result: {
          basePay: resultWithSnapshot.basePay,
          supplementPay: resultWithSnapshot.supplementPay,
          gross: resultWithSnapshot.gross,
          wagePeriods: resultWithSnapshot.wagePeriods,
        },
        verification: {
          wageSnapshotUsed: resultWithSnapshot.wagePeriods[0]?.baseRate === 200.0,
          supplementSnapshotUsed:
            resultWithSnapshot.wagePeriods.some((p) => p.supplementRate === 30),
          pass:
            resultWithSnapshot.wagePeriods[0]?.baseRate === 200.0 &&
            resultWithSnapshot.wagePeriods.some((p) => p.supplementRate === 30),
        },
      },

      test4_wage_snapshot_only: {
        description:
          "Wage snapshot only: should use 300 NOK wage + current preset supplements",
        shift: shiftWageSnapshotOnly,
        result: {
          basePay: resultWageSnapshotOnly.basePay,
          supplementPay: resultWageSnapshotOnly.supplementPay,
          gross: resultWageSnapshotOnly.gross,
          wagePeriods: resultWageSnapshotOnly.wagePeriods,
        },
        verification: {
          wageSnapshotUsed: resultWageSnapshotOnly.wagePeriods[0]?.baseRate === 300.0,
          presetSupplementsUsed: resultWageSnapshotOnly.wagePeriods.some(
            (p) => p.supplementRate === 22 || p.supplementRate === 45 // Preset evening rates
          ),
          pass: resultWageSnapshotOnly.wagePeriods[0]?.baseRate === 300.0,
        },
      },

      test5_supplement_snapshot_only: {
        description:
          "Supplement snapshot only: should use current wage (187.46) + snapshotted supplement (100 NOK)",
        shift: shiftSupplementSnapshotOnly,
        result: {
          basePay: resultSupplementSnapshotOnly.basePay,
          supplementPay: resultSupplementSnapshotOnly.supplementPay,
          gross: resultSupplementSnapshotOnly.gross,
          wagePeriods: resultSupplementSnapshotOnly.wagePeriods,
        },
        verification: {
          currentWageUsed:
            resultSupplementSnapshotOnly.wagePeriods[0]?.baseRate ===
            PRESET_WAGE_RATES["3"],
          supplementSnapshotUsed: resultSupplementSnapshotOnly.wagePeriods.some(
            (p) => p.supplementRate === 100
          ),
          pass:
            resultSupplementSnapshotOnly.wagePeriods[0]?.baseRate ===
              PRESET_WAGE_RATES["3"] &&
            resultSupplementSnapshotOnly.wagePeriods.some((p) => p.supplementRate === 100),
        },
      },
    },

    summary: {
      allTestsPassed:
        snapshotsPreset.hourly_wage_snapshot === PRESET_WAGE_RATES["3"] &&
        snapshotsCustom.hourly_wage_snapshot === 250 &&
        resultWithSnapshot.wagePeriods[0]?.baseRate === 200.0 &&
        resultWageSnapshotOnly.wagePeriods[0]?.baseRate === 300.0 &&
        resultSupplementSnapshotOnly.wagePeriods.some((p) => p.supplementRate === 100),
    },
  });
}
