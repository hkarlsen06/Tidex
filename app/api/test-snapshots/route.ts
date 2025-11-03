import { NextResponse } from 'next/server';
import {
  computeShift,
  PRESET_SUPPLEMENT_RULES,
  PRESET_WAGE_RATES,
  type ShiftRow,
  type UserSettings,
  type WageSnapshot,
} from '@/lib/payroll';

/**
 * Test endpoint for verifying wage snapshot system
 * Tests the priority order: new snapshot > old per-shift snapshot > fallback
 */
export async function GET() {
  const settings: UserSettings = {
    pause_deduction_enabled: false,
  };

  // Test 1: New wage snapshot system (Priority 1)
  const newSnapshot: WageSnapshot = {
    id: "test-new-snapshot",
    user_id: "test",
    from_date: null,
    hourly_wage: 200.0,
    wage_level: null,
    supplements: {
      rules: [{ days: [1, 2, 3, 4, 5], from: "17:00", to: "23:00", rate: 30 }],
    },
  };

  const shiftWithNewSnapshot: ShiftRow = {
    id: "test-1",
    shift_date: "2024-10-02",
    start_time: "18:00",
    end_time: "22:00",
    user_id: "test",
  };

  const result1 = computeShift(
    shiftWithNewSnapshot,
    settings,
    PRESET_SUPPLEMENT_RULES,
    newSnapshot
  );

  // Test 2: Old per-shift snapshot (Priority 2)
  const shiftWithOldSnapshot: ShiftRow = {
    id: "test-2",
    shift_date: "2024-10-02",
    start_time: "18:00",
    end_time: "22:00",
    hourly_wage_snapshot: 187.46,
    supplement_rules_snapshot: { rules: PRESET_SUPPLEMENT_RULES },
    user_id: "test",
  };

  const result2 = computeShift(
    shiftWithOldSnapshot,
    settings,
    PRESET_SUPPLEMENT_RULES,
    null
  );

  // Test 3: Fallback (Priority 3)
  const shiftFallback: ShiftRow = {
    id: "test-3",
    shift_date: "2024-10-02",
    start_time: "18:00",
    end_time: "22:00",
    user_id: "test",
  };

  const result3 = computeShift(
    shiftFallback,
    settings,
    PRESET_SUPPLEMENT_RULES,
    null
  );

  return NextResponse.json({
    tests: {
      test1_new_snapshot: {
        description: "New wage snapshot system (Priority 1)",
        expectedWage: 200.0,
        actualWage: result1.wagePeriods[0]?.baseRate,
        pass: result1.wagePeriods[0]?.baseRate === 200.0,
        result: {
          gross: result1.gross,
          basePay: result1.basePay,
          supplementPay: result1.supplementPay,
        },
      },
      test2_old_snapshot: {
        description: "Old per-shift snapshot (Priority 2)",
        expectedWage: 187.46,
        actualWage: result2.wagePeriods[0]?.baseRate,
        pass: result2.wagePeriods[0]?.baseRate === 187.46,
        result: {
          gross: result2.gross,
          basePay: result2.basePay,
          supplementPay: result2.supplementPay,
        },
      },
      test3_fallback: {
        description: "Fallback rate (Priority 3)",
        expectedWage: PRESET_WAGE_RATES["1"],
        actualWage: result3.wagePeriods[0]?.baseRate,
        pass: result3.wagePeriods[0]?.baseRate === PRESET_WAGE_RATES["1"],
        result: {
          gross: result3.gross,
          basePay: result3.basePay,
          supplementPay: result3.supplementPay,
        },
      },
    },
    summary: {
      allTestsPassed:
        result1.wagePeriods[0]?.baseRate === 200.0 &&
        result2.wagePeriods[0]?.baseRate === 187.46 &&
        result3.wagePeriods[0]?.baseRate === PRESET_WAGE_RATES["1"],
    },
  });
}
