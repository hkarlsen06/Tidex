import "server-only";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import {
  getCurrentYearMonth,
  getPreviousYearMonth,
  isDateInMonth,
} from "@/lib/date-utils";
import { hasShiftEnded } from "@/lib/shifts/hasShiftEnded";

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

/**
 * Format currency amount in Norwegian format
 * @example formatCurrency(15234.56) => "15 234 kr"
 */
function formatCurrency(value: number): string {
  return `${numberFormatter.format(Math.round(value))} kr`;
}

/**
 * Get the current month's total gross earnings for a user with comparison to last month
 */
export async function getMonthlyTotal(userId: string): Promise<{
  total: string;
  percentageChange?: number | "..";
  tillegg: string;
  gross: number;
  bonusPay: number;
  shiftCount: number;
  earnedToDate: string;
  earnedToDateGross: number;
}> {
  const { shifts } = await getComputedShifts(userId);

  // Get current month and year in UTC to ensure consistent date comparisons
  const { year: currentYear, month: currentMonth } = getCurrentYearMonth();
  const { year: lastMonthYear, month: lastMonth } = getPreviousYearMonth();

  // Filter shifts for current month
  const currentMonthShifts = shifts.filter((shift) =>
    isDateInMonth(shift.shift_date, currentYear, currentMonth)
  );

  // Filter shifts for last month
  const lastMonthShifts = shifts.filter((shift) =>
    isDateInMonth(shift.shift_date, lastMonthYear, lastMonth)
  );

  // Calculate current month totals
  const gross = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  const bonusPay = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.bonusPay || 0),
    0
  );

  const completedShifts = currentMonthShifts.filter((shift) =>
    hasShiftEnded(shift)
  );

  const earnedToDateGross = completedShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  // Calculate last month total for comparison
  const lastMonthGross = lastMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  // Calculate percentage change
  let percentageChange: number | ".." | undefined;
  if (lastMonthGross > 0) {
    percentageChange = Math.round(((gross - lastMonthGross) / lastMonthGross) * 100);
  } else if (gross > 0) {
    // New earnings from zero - show ".." indicator
    percentageChange = "..";
  }

  return {
    total: formatCurrency(gross),
    percentageChange,
    tillegg: formatCurrency(bonusPay),
    gross,
    bonusPay,
    shiftCount: currentMonthShifts.length,
    earnedToDate: formatCurrency(earnedToDateGross),
    earnedToDateGross,
  };
}
