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
  /**
   * Override tax settings for payout month calculations.
   * When provided, this tax rate is used instead of per-shift tax_percentage.
   * Use this for monthly totals where all shifts share the same payout month.
   */
  payoutTaxOverride?: {
    enabled: boolean;
    percentage: number;
  };
  /**
   * Set of shift IDs to exclude from totals (e.g., higher-earning conflicting shifts).
   * When shifts overlap, only the one with lowest earnings should count.
   */
  excludedShiftIds?: Set<string>;
};

/**
 * Calculate net amount for a single shift based on its tax settings
 */
function calculateShiftNet(
  shift: ShiftWithComputations,
  month: number | undefined,
  halfTaxMonth: number | null | undefined,
  fallbackTaxSettings?: TaxSettings,
  payoutTaxOverride?: { enabled: boolean; percentage: number }
): number {
  const gross = shift.computed.gross || 0;

  // If payoutTaxOverride is provided, use it instead of per-shift tax settings
  let taxEnabled: boolean;
  let taxPercentage: number;

  if (payoutTaxOverride) {
    taxEnabled = payoutTaxOverride.enabled;
    taxPercentage = payoutTaxOverride.enabled ? payoutTaxOverride.percentage : 0;
  } else {
    // Fall back to per-shift tax settings
    taxEnabled = shift.tax_enabled ?? fallbackTaxSettings?.enabled ?? false;
    taxPercentage = taxEnabled ? (shift.tax_percentage ?? fallbackTaxSettings?.percentage ?? 0) : 0;
  }

  // Apply half tax if payout month matches the configured half tax month
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
  payoutTaxOverride,
  excludedShiftIds,
}: ShiftTotalsOptions): ShiftTotals {
  // Filter out excluded shifts for totals calculation
  const includedShifts = excludedShiftIds
    ? shifts.filter(shift => !excludedShiftIds.has(shift.id))
    : shifts;

  const gross = includedShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const supplement = includedShifts.reduce(
    (sum, shift) => sum + (shift.computed.supplementPay || 0),
    0,
  );

  const completedShifts = includedShifts.filter((shift) => hasShiftEnded(shift, now));
  const completedGross = completedShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0,
  );

  // Calculate net per-shift using payout tax override if provided
  const net = includedShifts.reduce(
    (sum, shift) => sum + calculateShiftNet(shift, month, halfTaxMonth, taxSettings, payoutTaxOverride),
    0,
  );

  const completedNet = completedShifts.reduce(
    (sum, shift) => sum + calculateShiftNet(shift, month, halfTaxMonth, taxSettings, payoutTaxOverride),
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
  payoutTaxOverride,
  excludedShiftIds,
}: MonthlyTotalsOptions): MonthlyTotals {
  const monthShifts = filterShiftsForMonth(shifts, year, month);
  // Payout month = earnings month + 1 (used for half-tax detection)
  const payoutMonth = month >= 12 ? 1 : month + 1;
  const totals = summarizeShiftTotals({
    shifts: monthShifts,
    taxSettings,
    now,
    month: payoutMonth,
    halfTaxMonth,
    payoutTaxOverride,
    excludedShiftIds,
  });

  return {
    ...totals,
    shiftCount: monthShifts.length,
    shifts: monthShifts,
  };
}
