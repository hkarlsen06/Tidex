import { ShiftWithComputations } from "@/lib/payroll";
import { isDateInMonth } from "@/lib/date-utils";
import { hasShiftEnded } from "@/lib/shifts/hasShiftEnded";

export type TaxSettings = {
  enabled: boolean;
  percentage: number;
  halfTaxMonth?: number | null; // Month number (11=November, 12=December) for half tax deduction
};

export type ShiftTotals = {
  gross: number;
  net: number;
  supplement: number;
  completedGross: number;
  completedNet: number;
};

export type ShiftTotalsOptions = {
  shifts: ShiftWithComputations[];
  taxSettings?: TaxSettings;
  now?: Date;
  month?: number; // 1-12, used for half tax month detection
};

export function summarizeShiftTotals({
  shifts,
  taxSettings,
  now = new Date(),
  month,
}: ShiftTotalsOptions): ShiftTotals {
  const gross = shifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const supplement = shifts.reduce(
    (sum, shift) => sum + (shift.computed.supplementPay || 0),
    0,
  );

  const completedShifts = shifts.filter((shift) => hasShiftEnded(shift, now));
  const completedGross = completedShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0,
  );

  const taxEnabled = taxSettings?.enabled ?? false;
  let taxPercentage = taxEnabled ? Number(taxSettings?.percentage ?? 0) : 0;

  // Apply half tax if current month matches the configured half tax month
  const halfTaxMonth = taxSettings?.halfTaxMonth;
  if (taxEnabled && halfTaxMonth && month === halfTaxMonth) {
    taxPercentage = taxPercentage / 2;
  }

  const netMultiplier = taxEnabled ? 1 - taxPercentage / 100 : 1;

  const net = gross * netMultiplier;
  const completedNet = completedGross * netMultiplier;

  return {
    gross,
    net,
    supplement,
    completedGross,
    completedNet,
  };
}

export type MonthlyTotals = ShiftTotals & {
  shiftCount: number;
  shifts: ShiftWithComputations[];
};

export type MonthlyTotalsOptions = ShiftTotalsOptions & {
  year: number;
  month: number; // 1-12
};

export function filterShiftsForMonth(
  shifts: ShiftWithComputations[],
  year: number,
  month: number,
): ShiftWithComputations[] {
  return shifts.filter((shift) => isDateInMonth(shift.shift_date, year, month));
}

export function getMonthlyTotals({
  shifts,
  year,
  month,
  taxSettings,
  now,
}: MonthlyTotalsOptions): MonthlyTotals {
  const monthShifts = filterShiftsForMonth(shifts, year, month);
  const totals = summarizeShiftTotals({ shifts: monthShifts, taxSettings, now, month });

  return {
    ...totals,
    shiftCount: monthShifts.length,
    shifts: monthShifts,
  };
}
