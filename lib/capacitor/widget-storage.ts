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
 * Prepare shifts for widget and offline storage.
 * Filters to shifts from the first of the previous month through 90 days ahead.
 * Each shift uses its own tax_enabled/tax_percentage from the snapshot that applies to it.
 *
 * Storage window includes:
 * - Previous month: For offline dashboard payroll card (earnings paid this month)
 * - Current month: For offline dashboard total card
 * - Future 90 days: For widget and upcoming shifts list
 *
 * The widget itself filters to show only the next upcoming shift,
 * so extra shifts in storage don't affect widget behavior.
 */
export function prepareShiftsForStorage(
  shifts: ShiftWithComputations[],
  locale: string,
  currencySymbol: string
): StoredShiftData[] {
  const now = new Date();

  // Include previous month for offline dashboard payroll card
  // (shows last month's earnings being paid this month)
  const minDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const minDateStr = getLocalDateString(minDate);

  // Future window: 90 days from now
  const maxDate = new Date(now);
  maxDate.setDate(maxDate.getDate() + 90);
  const maxDateStr = getLocalDateString(maxDate);

  // Filter to shifts within the storage window (prev month through 90 days ahead)
  return shifts
    .filter((s) => s.shift_date >= minDateStr && s.shift_date <= maxDateStr)
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
