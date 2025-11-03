import { NextResponse } from 'next/server';
import {
  computeShift,
  PRESET_SUPPLEMENT_RULES,
  PRESET_WAGE_RATES,
  type ShiftRow,
  type UserSettings,
  type WageSnapshot,
} from '@/lib/payroll';

export async function GET() {
  const shift: ShiftRow = {
    id: "test",
    shift_date: "2024-10-02", // Thursday (day 4)
    start_time: "16:00",
    end_time: "23:15",
    hourly_wage_snapshot: null,
    user_id: "test",
  };

  const settings: UserSettings = {
    pause_deduction_enabled: true,
    pause_deduction_method: "proportional",
    pause_threshold_hours: 5.5,
    pause_deduction_minutes: 30,
  };

  // Create a test wage snapshot (tariff level 3)
  const snapshot: WageSnapshot = {
    id: "test-snapshot",
    user_id: "test",
    from_date: null, // baseline
    hourly_wage: PRESET_WAGE_RATES["3"], // 187.46
    wage_level: 3,
    supplements: { rules: PRESET_SUPPLEMENT_RULES },
  };

  const result = computeShift(shift, settings, PRESET_SUPPLEMENT_RULES, snapshot);

  return NextResponse.json({
    shift,
    settings,
    result: {
      basePay: result.basePay,
      supplementPay: result.supplementPay,
      gross: result.gross,
      paidHours: result.paidHours,
      durationHours: result.durationHours,
      wagePeriods: result.wagePeriods,
      originalWagePeriods: result.originalWagePeriods,
      breakAudit: result.breakAudit,
    },
  });
}
