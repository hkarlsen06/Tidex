import { ShiftActivity, type StoredShiftData } from "./shift-activity";
import { isIOSPlatform } from "./platform";
import type { ShiftWithComputations } from "@/lib/payroll/types";

/**
 * Calculate average supplement rate from wage periods.
 * Returns weighted average based on period duration.
 */
export function calculateAverageSupplementRate(shift: ShiftWithComputations): number {
  const periods = shift.computed.wagePeriods;
  if (periods.length === 0) return 0;

  let totalWeightedSupplement = 0;
  let totalMinutes = 0;

  for (const period of periods) {
    const minutes = period.toMin - period.fromMin;
    totalWeightedSupplement += period.supplementRate * minutes;
    totalMinutes += minutes;
  }

  return totalMinutes > 0 ? totalWeightedSupplement / totalMinutes : 0;
}

/**
 * Get today's date string in local timezone (YYYY-MM-DD).
 * Uses local date to ensure consistent behavior across timezones.
 */
function getLocalDateString(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/**
 * Prepare shifts for widget storage.
 * Filters to shifts within the next 7 days (today through today+7) in user's local timezone.
 * Each shift uses its own tax_enabled/tax_percentage from the snapshot that applies to it.
 */
export function prepareShiftsForStorage(
  shifts: ShiftWithComputations[],
  locale: string,
  currencySymbol: string
): StoredShiftData[] {
  const now = new Date();
  const todayStr = getLocalDateString(now);

  // Widget window: today through end of day 7 days from now (inclusive)
  const maxDate = new Date(now);
  maxDate.setDate(maxDate.getDate() + 7);
  const maxDateStr = getLocalDateString(maxDate);

  // Filter to upcoming shifts within the widget window
  return shifts
    .filter((s) => s.shift_date >= todayStr && s.shift_date <= maxDateStr)
    .map((shift) => {
      const supplementRate = calculateAverageSupplementRate(shift);
      const hourlyWage =
        shift.computed.paidHours > 0
          ? shift.computed.basePay / shift.computed.paidHours
          : 0;

      // Use the shift's own tax settings from its applicable snapshot
      const taxRate = shift.tax_enabled
        ? (shift.tax_percentage ?? 0) / 100
        : 0;

      return {
        shiftId: shift.id,
        shiftDate: shift.shift_date,
        startTime: shift.start_time,
        endTime: shift.end_time,
        hourlyWage,
        supplementRatePerHour: supplementRate,
        totalGrossEstimate: shift.computed.gross,
        locale,
        currencySymbol,
        taxRate,
      };
    });
}

/**
 * Save shifts to iOS widget shared storage.
 * No-op on non-iOS platforms. Errors are logged but not thrown.
 */
export async function saveShiftsToWidgetStorage(
  shifts: ShiftWithComputations[],
  locale: string,
  currencySymbol: string
): Promise<void> {
  if (!isIOSPlatform()) return;

  try {
    const storedShifts = prepareShiftsForStorage(shifts, locale, currencySymbol);
    await ShiftActivity.saveShiftsToSharedStorage({
      shifts: JSON.stringify(storedShifts),
    });
  } catch (error) {
    console.error("[WidgetStorage] Failed to save shifts:", error);
  }
}
