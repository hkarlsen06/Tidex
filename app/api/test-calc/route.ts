import { NextResponse } from 'next/server';
import {
  computeShift,
  PRESET_SUPPLEMENT_RULES,
  type ShiftRow,
  type UserSettings,
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
    use_preset: true,
    current_wage_level: 3,
    pause_deduction_enabled: true,
    pause_deduction_method: "proportional",
    pause_threshold_hours: 5.5,
    pause_deduction_minutes: 30,
  };

  const result = computeShift(shift, settings, PRESET_SUPPLEMENT_RULES);

  return NextResponse.json({
    shift,
    settings,
    result: {
      basePay: result.basePay,
      bonusPay: result.bonusPay,
      gross: result.gross,
      paidHours: result.paidHours,
      durationHours: result.durationHours,
      wagePeriods: result.wagePeriods,
      originalWagePeriods: result.originalWagePeriods,
      breakAudit: result.breakAudit,
    },
  });
}
