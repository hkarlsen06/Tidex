import "server-only";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import {
  getCurrentYearMonth,
  getPreviousYearMonth,
  isDateInMonth,
  parseDateAsUTC,
} from "@/lib/date-utils";

export type StatsData = {
  currentMonth: {
    totalEarnings: number;
    totalHours: number;
    shiftCount: number;
    averageRate: number;
  };
  lastMonth: {
    totalEarnings: number;
    totalHours: number;
    shiftCount: number;
  };
  percentageChange: number | null;
  yearToDate: {
    totalEarnings: number;
    totalHours: number;
    shiftCount: number;
  };
};

export async function getStatsData(userId: string): Promise<StatsData> {
  const { shifts } = await getComputedShifts(userId);

  // Use UTC-based date handling for consistent month/year comparisons
  const { year: currentYear, month: currentMonth } = getCurrentYearMonth();
  const { year: lastMonthYear, month: lastMonth } = getPreviousYearMonth();

  // Current month stats
  const monthShifts = shifts.filter((shift) =>
    isDateInMonth(shift.shift_date, currentYear, currentMonth)
  );
  const monthEarnings = monthShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const monthHours = monthShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);
  const monthAvgRate = monthHours > 0 ? monthEarnings / monthHours : 0;

  // Last month stats
  const lastMonthShifts = shifts.filter((shift) =>
    isDateInMonth(shift.shift_date, lastMonthYear, lastMonth)
  );
  const lastMonthEarnings = lastMonthShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const lastMonthHours = lastMonthShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);

  // Calculate percentage change
  let percentageChange: number | null = null;
  if (lastMonthEarnings > 0) {
    percentageChange = Math.round(((monthEarnings - lastMonthEarnings) / lastMonthEarnings) * 100);
  }

  // Year-to-date stats (only up to today)
  const now = new Date();
  const ytdShifts = shifts.filter((shift) => {
    const shiftDate = parseDateAsUTC(shift.shift_date);
    return shiftDate.getUTCFullYear() === currentYear && shiftDate <= now;
  });
  const ytdEarnings = ytdShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const ytdHours = ytdShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);

  return {
    currentMonth: {
      totalEarnings: monthEarnings,
      totalHours: monthHours,
      shiftCount: monthShifts.length,
      averageRate: monthAvgRate,
    },
    lastMonth: {
      totalEarnings: lastMonthEarnings,
      totalHours: lastMonthHours,
      shiftCount: lastMonthShifts.length,
    },
    percentageChange,
    yearToDate: {
      totalEarnings: ytdEarnings,
      totalHours: ytdHours,
      shiftCount: ytdShifts.length,
    },
  };
}
