import { NextResponse } from 'next/server';
import { computeShift } from '@/lib/payroll/calc';
import type { ShiftRow, UserSettings, BonusRule } from '@/lib/payroll/types';

const PRESET_RULES: BonusRule[] = [
  { days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22 },
  { days: [1, 2, 3, 4, 5], from: "21:00", to: "23:59", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 45 },
  { days: [6], from: "15:00", to: "18:00", rate: 55 },
  { days: [6], from: "18:00", to: "23:59", rate: 110 },
  { days: [7], from: "00:00", to: "23:59", rate: 115 },
];

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
    break_enabled: true,
    break_method: "proportional",
    break_threshold_hours: 5.5,
    break_deduction_minutes: 30,
  };

  const result = computeShift(shift, settings, PRESET_RULES);

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
