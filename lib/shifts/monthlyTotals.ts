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
  /**
   * @deprecated Tax settings are now per-shift. This is kept for backward compatibility.
   * If provided, it will be used as a fallback when shifts don't have tax_enabled/tax_percentage.
   */
  taxSettings?: TaxSettings;
  now?: Date;
  month?: number; // 1-12, used for half tax month detection
  /**
   * Global half_tax_month from user settings
   * Used when calculating tax for the payout month
   */
  halfTaxMonth?: number | null;
};

/**
 * Calculate net amount for a single shift based on its tax settings
 */
function calculateShiftNet(
  shift: ShiftWithComputations,
  month: number | undefined,
  halfTaxMonth: number | null | undefined,
  fallbackTaxSettings?: TaxSettings
): number {
  const gross = shift.computed.gross || 0;

  // Use per-shift tax settings if available, otherwise fall back to global settings
  const taxEnabled = shift.tax_enabled ?? fallbackTaxSettings?.enabled ?? false;
  let taxPercentage = taxEnabled ? (shift.tax_percentage ?? fallbackTaxSettings?.percentage ?? 0) : 0;

  // Apply half tax if current month matches the configured half tax month
  const effectiveHalfTaxMonth = halfTaxMonth ?? fallbackTaxSettings?.halfTaxMonth;
  if (taxEnabled && effectiveHalfTaxMonth && month === effectiveHalfTaxMonth) {
    taxPercentage = taxPercentage / 2;
  }

  const netMultiplier = taxEnabled ? 1 - taxPercentage / 100 : 1;
  return gross * netMultiplier;
}

export function summarizeShiftTotals({
  shifts,
  taxSettings,
  now = new Date(),
  month,
  halfTaxMonth,
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

  // Calculate net per-shift (each shift may have different tax settings)
  const net = shifts.reduce(
    (sum, shift) => sum + calculateShiftNet(shift, month, halfTaxMonth, taxSettings),
    0,
  );

  const completedNet = completedShifts.reduce(
    (sum, shift) => sum + calculateShiftNet(shift, month, halfTaxMonth, taxSettings),
    0,
  );

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
  halfTaxMonth,
}: MonthlyTotalsOptions): MonthlyTotals {
  const monthShifts = filterShiftsForMonth(shifts, year, month);
  const totals = summarizeShiftTotals({ shifts: monthShifts, taxSettings, now, month, halfTaxMonth });

  return {
    ...totals,
    shiftCount: monthShifts.length,
    shifts: monthShifts,
  };
}
