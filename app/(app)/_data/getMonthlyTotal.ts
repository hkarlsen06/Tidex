import "server-only";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";

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
  percentageChange?: number;
  tillegg: string;
  gross: number;
  bonusPay: number;
  shiftCount: number;
}> {
  const shifts = await getComputedShifts(userId);

  // Get current month and year
  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth() + 1; // 1-based month
  // Filter shifts for current month
  const currentMonthShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return (
      shiftDate.getFullYear() === currentYear &&
      shiftDate.getMonth() + 1 === currentMonth
    );
  });

  // Filter shifts for last month
  const lastMonthDate = new Date(currentYear, currentMonth - 2, 1); // month is 0-indexed for Date constructor
  const lastMonthYear = lastMonthDate.getFullYear();
  const lastMonth = lastMonthDate.getMonth() + 1;

  const lastMonthShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return (
      shiftDate.getFullYear() === lastMonthYear &&
      shiftDate.getMonth() + 1 === lastMonth
    );
  });

  // Calculate current month totals
  const gross = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  const bonusPay = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.bonusPay || 0),
    0
  );

  // Calculate last month total for comparison
  const lastMonthGross = lastMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  // Calculate percentage change
  let percentageChange: number | undefined;
  if (lastMonthGross > 0) {
    percentageChange = Math.round(((gross - lastMonthGross) / lastMonthGross) * 100);
  }

  return {
    total: formatCurrency(gross),
    percentageChange,
    tillegg: formatCurrency(bonusPay),
    gross,
    bonusPay,
    shiftCount: currentMonthShifts.length,
  };
}
