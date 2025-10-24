import "server-only";
import { cache } from "react";
import { unstable_cache } from "next/cache";
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
 * Internal implementation of getMonthlyTotal
 */
async function getMonthlyTotalInternal(userId: string): Promise<{
  total: string;
  percentageChange?: number | "..";
  tillegg: string;
  gross: number;
  supplementPay: number;
  shiftCount: number;
  earnedToDate: string;
  earnedToDateGross: number;
}> {
  // Load last 3 months for current + previous month comparison
  const threeMonthsAgo = new Date();
  threeMonthsAgo.setUTCMonth(threeMonthsAgo.getUTCMonth() - 3);
  const startDate = threeMonthsAgo.toISOString().split('T')[0];

  const { shifts } = await getComputedShifts(userId, {
    startDate,
    limit: 200 // Reasonable limit for 3 months
  });

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

  const supplementPay = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.supplementPay || 0),
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
    tillegg: formatCurrency(supplementPay),
    gross,
    supplementPay,
    shiftCount: currentMonthShifts.length,
    earnedToDate: formatCurrency(earnedToDateGross),
    earnedToDateGross,
  };
}

/**
 * Get the current month's total gross earnings for a user with comparison to last month
 * - Uses React cache() for request deduplication
 * - Uses Next.js Data Cache for persistent caching (5 min TTL)
 */
export const getMonthlyTotal = cache(async (userId: string): Promise<{
  total: string;
  percentageChange?: number | "..";
  tillegg: string;
  gross: number;
  supplementPay: number;
  shiftCount: number;
  earnedToDate: string;
  earnedToDateGross: number;
}> => {
  const cacheKey = `monthly-total-${userId}`;

  const getCached = unstable_cache(
    async () => getMonthlyTotalInternal(userId),
    [cacheKey],
    {
      tags: [`user-shifts-${userId}`],
      revalidate: 300 // 5 minutes
    }
  );

  return getCached();
});
