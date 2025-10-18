import "server-only";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import {
  getCurrentYearMonth,
  getPreviousYearMonth,
  isDateInMonth,
  parseDateAsUTC,
  getYearMonth,
} from "@/lib/date-utils";

export type MonthlyData = {
  month: string; // "Jan", "Feb", etc.
  fullMonth: string; // "Januar", "Februar", etc.
  earnings: number;
  hours: number;
  shifts: number;
  year: number;
  monthNumber: number; // 1-12
};

export type DailyData = {
  date: string; // "Mon", "Tue", etc. or full date
  fullDay: string; // "Mandag", "Tirsdag", etc.
  earnings: number;
  hours: number;
  shifts: number;
  fullDate: string; // YYYY-MM-DD
};

export type DayOfWeekData = {
  day: string;
  fullDay: string; // "Mandag", "Tirsdag", etc.
  averageEarnings: number;
  totalShifts: number;
};

export type DailyCumulativeData = {
  day: string; // "1", "2", "3", etc.
  dayNumber: number; // 1-31
  currentMonth: number; // Cumulative earnings for current month
  lastMonth: number; // Cumulative earnings for last month (same day)
  isToday: boolean;
  isFuture: boolean;
};

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
  // New chart data
  last6Months: MonthlyData[];
  thisWeek: DailyData[];
  byDayOfWeek: DayOfWeekData[];
  thisMonthCumulative: DailyCumulativeData[];
};

const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Des"];
const FULL_MONTH_NAMES = ["Januar", "Februar", "Mars", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Desember"];
const DAY_NAMES = ["Søn", "Man", "Tir", "Ons", "Tor", "Fre", "Lør"];
const FULL_DAY_NAMES = ["Søndag", "Mandag", "Tirsdag", "Onsdag", "Torsdag", "Fredag", "Lørdag"];

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

  // Last 6 months breakdown
  const last6Months: MonthlyData[] = [];
  for (let i = 5; i >= 0; i--) {
    const targetDate = new Date(Date.UTC(currentYear, currentMonth - 1 - i, 1));
    const { year, month } = getYearMonth(targetDate);

    const monthShifts = shifts.filter((shift) => isDateInMonth(shift.shift_date, year, month));
    const earnings = monthShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
    const hours = monthShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);

    last6Months.push({
      month: MONTH_NAMES[month - 1],
      fullMonth: FULL_MONTH_NAMES[month - 1],
      earnings,
      hours,
      shifts: monthShifts.length,
      year,
      monthNumber: month,
    });
  }

  // This week's daily breakdown (Monday to Sunday of current week)
  const thisWeek: DailyData[] = [];

  // Get the current day of week (0 = Sunday, 1 = Monday, etc.)
  const currentDayOfWeek = now.getUTCDay();
  // Calculate days since Monday (treat Sunday as 7)
  const daysSinceMonday = currentDayOfWeek === 0 ? 6 : currentDayOfWeek - 1;

  // Start from Monday of this week
  for (let i = 0; i < 7; i++) {
    const daysFromMonday = i - daysSinceMonday;
    const targetDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + daysFromMonday));
    const dateString = targetDate.toISOString().split('T')[0];

    const dayShifts = shifts.filter((shift) => shift.shift_date === dateString);
    const earnings = dayShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
    const hours = dayShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);

    // Map day of week: 0=Sunday -> use index 0, 1=Monday -> use index 1, etc.
    const dayOfWeek = targetDate.getUTCDay();
    const dayName = DAY_NAMES[dayOfWeek];

    thisWeek.push({
      date: dayName,
      fullDay: FULL_DAY_NAMES[dayOfWeek],
      earnings,
      hours,
      shifts: dayShifts.length,
      fullDate: dateString,
    });
  }

  // By day of week aggregation
  const dayOfWeekMap = new Map<number, { earnings: number; hours: number; shifts: number }>();

  for (const shift of shifts) {
    const shiftDate = parseDateAsUTC(shift.shift_date);
    const dayOfWeek = shiftDate.getUTCDay();

    const existing = dayOfWeekMap.get(dayOfWeek) || { earnings: 0, hours: 0, shifts: 0 };
    dayOfWeekMap.set(dayOfWeek, {
      earnings: existing.earnings + (shift.computed.gross || 0),
      hours: existing.hours + (shift.computed.paidHours || 0),
      shifts: existing.shifts + 1,
    });
  }

  // Prefer Monday first; only include Sunday if user has worked Sunday shifts
  const sundayShifts = dayOfWeekMap.get(0)?.shifts ?? 0;
  const dayOrder = [1, 2, 3, 4, 5, 6]; // Monday through Saturday
  if (sundayShifts > 0) {
    dayOrder.push(0); // Append Sunday last
  }

  const byDayOfWeek: DayOfWeekData[] = dayOrder.map((dayIndex) => {
    const data = dayOfWeekMap.get(dayIndex) || { earnings: 0, hours: 0, shifts: 0 };
    const averageEarnings = data.shifts > 0 ? data.earnings / data.shifts : 0;
    return {
      day: DAY_NAMES[dayIndex],
      fullDay: FULL_DAY_NAMES[dayIndex],
      averageEarnings,
      totalShifts: data.shifts,
    };
  });

  // Monthly cumulative comparison (current month vs last month by day)
  const thisMonthCumulative: DailyCumulativeData[] = [];

  // Get number of days in current month
  const daysInCurrentMonth = new Date(Date.UTC(currentYear, currentMonth, 0)).getUTCDate();

  // Get today's day number
  const todayDayNumber = now.getUTCDate();

  // Build daily cumulative arrays for both months
  let currentMonthCumulative = 0;
  let lastMonthCumulative = 0;

  for (let day = 1; day <= daysInCurrentMonth; day++) {
    // Current month - check if there are shifts on this day
    const currentDayDate = new Date(Date.UTC(currentYear, currentMonth - 1, day)).toISOString().split('T')[0];
    const currentDayShifts = shifts.filter((shift) => shift.shift_date === currentDayDate);
    const currentDayEarnings = currentDayShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
    currentMonthCumulative += currentDayEarnings;

    // Last month - check if there are shifts on this day (if it exists in last month)
    const lastMonthDate = new Date(Date.UTC(lastMonthYear, lastMonth - 1, day));
    const daysInLastMonth = new Date(Date.UTC(lastMonthYear, lastMonth, 0)).getUTCDate();

    if (day <= daysInLastMonth) {
      const lastDayDate = lastMonthDate.toISOString().split('T')[0];
      const lastDayShifts = shifts.filter((shift) => shift.shift_date === lastDayDate);
      const lastDayEarnings = lastDayShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
      lastMonthCumulative += lastDayEarnings;
    }

    thisMonthCumulative.push({
      day: day.toString(),
      dayNumber: day,
      currentMonth: currentMonthCumulative,
      lastMonth: lastMonthCumulative,
      isToday: day === todayDayNumber,
      isFuture: day > todayDayNumber,
    });
  }

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
    last6Months,
    thisWeek,
    byDayOfWeek,
    thisMonthCumulative,
  };
}
