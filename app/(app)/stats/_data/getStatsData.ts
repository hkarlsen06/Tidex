import "server-only";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";

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

  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth() + 1;

  // Current month stats
  const monthShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return shiftDate.getFullYear() === currentYear && shiftDate.getMonth() + 1 === currentMonth;
  });
  const monthEarnings = monthShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const monthHours = monthShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);
  const monthAvgRate = monthHours > 0 ? monthEarnings / monthHours : 0;

  // Last month stats
  const lastMonthDate = new Date(currentYear, currentMonth - 2, 1);
  const lastMonthYear = lastMonthDate.getFullYear();
  const lastMonth = lastMonthDate.getMonth() + 1;

  const lastMonthShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return shiftDate.getFullYear() === lastMonthYear && shiftDate.getMonth() + 1 === lastMonth;
  });
  const lastMonthEarnings = lastMonthShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const lastMonthHours = lastMonthShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);

  // Calculate percentage change
  let percentageChange: number | null = null;
  if (lastMonthEarnings > 0) {
    percentageChange = Math.round(((monthEarnings - lastMonthEarnings) / lastMonthEarnings) * 100);
  }

  // Year-to-date stats (only up to today)
  const ytdShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return shiftDate.getFullYear() === currentYear && shiftDate <= now;
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
