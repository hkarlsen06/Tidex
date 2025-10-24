import "server-only";
import { cache } from "react";
import { unstable_cache } from "next/cache";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import {
  getCurrentYearMonth,
  isDateInMonth,
  parseDateAsUTC,
  getYearMonth,
} from "@/lib/date-utils";

/**
 * Helper to get start date for stats (12 months ago for comprehensive stats)
 */
function getStatsStartDate(): string {
  const date = new Date();
  date.setUTCMonth(date.getUTCMonth() - 12);
  date.setUTCDate(1);
  return date.toISOString().split('T')[0];
}

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

export type YearlyCumulativeData = {
  month: string; // "Jan", "Feb", etc.
  fullMonth: string; // "Januar", "Februar", etc.
  monthNumber: number; // 1-12
  cumulative: number; // Cumulative earnings up to this month
  isProjected: boolean; // Whether this is a projected value
};

export type MonthlySummary = {
  key: string; // YYYY-MM
  year: number;
  month: number; // 1-12
  totalGross: number;
  totalNet: number;
  totalHours: number;
  shiftCount: number;
  averageRate: number;
};

export type SupplementBreakdown = {
  basePay: number;
  supplementPay: number;
  basePercentage: number;
  supplementPercentage: number;
};

export type MonthlyGoal = {
  enabled: boolean;
  target: number;
  progress: number; // current earnings
  percentage: number; // progress as % of goal
  remaining: number; // amount left to reach goal
};

export type StatsData = {
  focusMonth: {
    year: number;
    month: number;
  };
  tax: {
    enabled: boolean;
    percentage: number;
  };
  currentMonth: {
    totalEarnings: number;
    totalEarningsNet: number;
    totalHours: number;
    shiftCount: number;
    averageRate: number;
  };
  lastMonth: {
    totalEarnings: number;
    totalEarningsNet: number;
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
  yearlyCumulative: YearlyCumulativeData[];
  monthlySummaries: MonthlySummary[];
  currentMonthBreakdown: SupplementBreakdown;
  monthlyGoal: MonthlyGoal;
};

const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Des"];
const FULL_MONTH_NAMES = ["Januar", "Februar", "Mars", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Desember"];
const DAY_NAMES = ["Søn", "Man", "Tir", "Ons", "Tor", "Fre", "Lør"];
const FULL_DAY_NAMES = ["Søndag", "Mandag", "Tirsdag", "Onsdag", "Torsdag", "Fredag", "Lørdag"];

type StatsOptions = {
  year?: number;
  month?: number; // 1-12
};

/**
 * Internal implementation of getStatsData
 */
async function getStatsDataInternal(userId: string, options: StatsOptions = {}): Promise<StatsData> {
  // Load last 12 months of shifts for stats calculations
  const { shifts, settings } = await getComputedShifts(userId, {
    startDate: getStatsStartDate(),
    limit: 1000 // Reasonable limit for 12 months of data
  });

  // Determine focus month (defaults to current UTC month)
  const { year: currentYearDefault, month: currentMonthDefault } = getCurrentYearMonth();
  const focusYear = options.year ?? currentYearDefault;
  const focusMonth = options.month ?? currentMonthDefault;

  const previousMonthDate = new Date(Date.UTC(focusYear, focusMonth - 2, 1));
  const { year: lastMonthYear, month: lastMonth } = getYearMonth(previousMonthDate);

  const realNow = new Date();
  const isCurrentSelection =
    focusYear === realNow.getUTCFullYear() && focusMonth === realNow.getUTCMonth() + 1;
  const monthEndDate = new Date(Date.UTC(focusYear, focusMonth, 0));
  const cutoffDate = isCurrentSelection ? realNow : monthEndDate;

  const taxEnabled = settings.tax_deduction_enabled ?? false;
  const taxPercentage = taxEnabled ? Number(settings.tax_percentage ?? 0) : 0;
  const netMultiplier = taxEnabled ? 1 - taxPercentage / 100 : 1;
  const applyNet = (gross: number) =>
    taxEnabled ? +(gross * netMultiplier).toFixed(2) : gross;

  // Pre-compute monthly aggregates for client-side month switching
  const monthlyMap = new Map<string, MonthlySummary>();

  for (const shift of shifts) {
    const shiftDate = parseDateAsUTC(shift.shift_date);
    const year = shiftDate.getUTCFullYear();
    const monthIndex = shiftDate.getUTCMonth() + 1;
    const key = `${year}-${String(monthIndex).padStart(2, "0")}`;

    const gross = shift.computed.gross || 0;
    const hours = shift.computed.paidHours || 0;

    const existing = monthlyMap.get(key) ?? {
      key,
      year,
      month: monthIndex,
      totalGross: 0,
      totalNet: 0,
      totalHours: 0,
      shiftCount: 0,
      averageRate: 0,
    };

    existing.totalGross += gross;
    existing.totalNet += taxEnabled ? gross * netMultiplier : gross;
    existing.totalHours += hours;
    existing.shiftCount += 1;

    monthlyMap.set(key, existing);
  }

  const monthlySummaries = Array.from(monthlyMap.values())
    .map((summary) => {
      const totalGross = +summary.totalGross.toFixed(2);
      const totalNet = +summary.totalNet.toFixed(2);
      const totalHours = +summary.totalHours.toFixed(2);
      const averageRate =
        totalHours > 0 ? +(totalGross / totalHours).toFixed(2) : 0;

      return {
        ...summary,
        totalGross,
        totalNet,
        totalHours,
        shiftCount: summary.shiftCount,
        averageRate,
      };
    })
    .sort((a, b) => {
      if (a.year !== b.year) return a.year - b.year;
      return a.month - b.month;
    });

  // Current month stats
  const monthShifts = shifts.filter((shift) =>
    isDateInMonth(shift.shift_date, focusYear, focusMonth)
  );
  const monthEarnings = monthShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const monthHours = monthShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);
  const monthAvgRate = monthHours > 0 ? monthEarnings / monthHours : 0;
  const monthEarningsNet = applyNet(monthEarnings);

  // Calculate supplement breakdown for current month
  const monthBasePay = monthShifts.reduce((sum, shift) => sum + (shift.computed.basePay || 0), 0);
  const monthSupplementPay = monthShifts.reduce((sum, shift) => sum + (shift.computed.supplementPay || 0), 0);
  const totalPay = monthBasePay + monthSupplementPay;
  const basePercentage = totalPay > 0 ? (monthBasePay / totalPay) * 100 : 0;
  const supplementPercentage = totalPay > 0 ? (monthSupplementPay / totalPay) * 100 : 0;

  // Calculate monthly goal progress
  const monthlyGoalTarget = settings.monthly_goal ? Number(settings.monthly_goal) : 0;
  const monthlyGoalEnabled = monthlyGoalTarget > 0;
  const goalProgress = taxEnabled ? monthEarningsNet : monthEarnings;
  const goalPercentage = monthlyGoalEnabled ? (goalProgress / monthlyGoalTarget) * 100 : 0;
  const goalRemaining = monthlyGoalEnabled ? Math.max(0, monthlyGoalTarget - goalProgress) : 0;

  // Last month stats
  const lastMonthShifts = shifts.filter((shift) =>
    isDateInMonth(shift.shift_date, lastMonthYear, lastMonth)
  );
  const lastMonthEarnings = lastMonthShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const lastMonthHours = lastMonthShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);
  const lastMonthEarningsNet = applyNet(lastMonthEarnings);

  // Calculate percentage change
  let percentageChange: number | null = null;
  const displayCurrent = taxEnabled ? monthEarningsNet : monthEarnings;
  const displayLast = taxEnabled ? lastMonthEarningsNet : lastMonthEarnings;
  if (displayLast > 0) {
    percentageChange = Math.round(((displayCurrent - displayLast) / displayLast) * 100);
  }

  // Year-to-date stats (only up to today)
  const ytdShifts = shifts.filter((shift) => {
    const shiftDate = parseDateAsUTC(shift.shift_date);
    return shiftDate.getUTCFullYear() === focusYear && shiftDate <= cutoffDate;
  });
  const ytdEarnings = ytdShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
  const ytdHours = ytdShifts.reduce((sum, shift) => sum + (shift.computed.paidHours || 0), 0);

  // Last 6 months breakdown
  const last6Months: MonthlyData[] = [];
  for (let i = 5; i >= 0; i--) {
    const targetDate = new Date(Date.UTC(focusYear, focusMonth - 1 - i, 1));
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
  // Always uses the ACTUAL current week, not the selected month
  const thisWeek: DailyData[] = [];

  // Get the current day of week (0 = Sunday, 1 = Monday, etc.)
  const currentDayOfWeek = realNow.getUTCDay();
  // Calculate days since Monday (treat Sunday as 7)
  const daysSinceMonday = currentDayOfWeek === 0 ? 6 : currentDayOfWeek - 1;

  // Start from Monday of the current week
  for (let i = 0; i < 7; i++) {
    const daysFromMonday = i - daysSinceMonday;
    const targetDate = new Date(
      Date.UTC(
        realNow.getUTCFullYear(),
        realNow.getUTCMonth(),
        realNow.getUTCDate() + daysFromMonday
      )
    );
    const dateString = targetDate.toISOString().split('T')[0];

    // Find shifts for this day from ALL shifts, not just the selected month
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

  // By day of week aggregation (using year-to-date data for consistency)
  const dayOfWeekMap = new Map<number, { earnings: number; hours: number; shifts: number }>();

  for (const shift of ytdShifts) {
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
  const daysInCurrentMonth = monthEndDate.getUTCDate();

  // Determine day number cut-off (today if current month, otherwise end of month)
  const todayDayNumber = isCurrentSelection ? realNow.getUTCDate() : daysInCurrentMonth;

  // Build daily cumulative arrays for both months
  let currentMonthCumulative = 0;
  let lastMonthCumulative = 0;

  for (let day = 1; day <= daysInCurrentMonth; day++) {
    // Current month - check if there are shifts on this day
    const currentDayDate = new Date(Date.UTC(focusYear, focusMonth - 1, day)).toISOString().split('T')[0];
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
      isToday: isCurrentSelection && day === todayDayNumber,
      isFuture: day > todayDayNumber,
    });
  }

  // Yearly cumulative with projection starting from today
  const yearlyCumulative: YearlyCumulativeData[] = [];
  let yearCumulative = 0;

  // Calculate how many days have passed in the year so far
  const yearStart = new Date(Date.UTC(focusYear, 0, 1));
  const daysSoFar = isCurrentSelection
    ? Math.ceil((realNow.getTime() - yearStart.getTime()) / (1000 * 60 * 60 * 24))
    : 365; // If not current year, use full year

  // Calculate average daily earnings for projection
  const averageDailyEarnings = daysSoFar > 0 ? ytdEarnings / daysSoFar : 0;

  const currentMonthIndex = realNow.getUTCMonth() + 1;
  const currentDayOfMonth = realNow.getUTCDate();

  for (let monthIndex = 1; monthIndex <= 12; monthIndex++) {
    const monthKey = `${focusYear}-${String(monthIndex).padStart(2, "0")}`;
    const monthSummary = monthlySummaries.find((s) => s.key === monthKey);

    const isCurrentMonth = isCurrentSelection && monthIndex === currentMonthIndex;
    const isInFuture = isCurrentSelection && monthIndex > currentMonthIndex;

    if (monthSummary && monthIndex < currentMonthIndex) {
      // Past months: use actual data
      yearCumulative += monthSummary.totalGross;
      yearlyCumulative.push({
        month: MONTH_NAMES[monthIndex - 1],
        fullMonth: FULL_MONTH_NAMES[monthIndex - 1],
        monthNumber: monthIndex,
        cumulative: yearCumulative,
        isProjected: false,
      });
    } else if (isCurrentMonth) {
      // Current month: split into actual (up to today) and projected (rest of month)
      const actualEarnings = monthSummary?.totalGross || 0;
      yearCumulative += actualEarnings;

      // Add actual data point for current month
      yearlyCumulative.push({
        month: MONTH_NAMES[monthIndex - 1],
        fullMonth: FULL_MONTH_NAMES[monthIndex - 1],
        monthNumber: monthIndex,
        cumulative: yearCumulative,
        isProjected: false,
      });

      // Calculate remaining days in current month and project earnings
      const daysInMonth = new Date(Date.UTC(focusYear, monthIndex, 0)).getUTCDate();
      const remainingDays = daysInMonth - currentDayOfMonth;
      const projectedRemainingEarnings = averageDailyEarnings * remainingDays;

      // Add projected data point for current month (end of month projection)
      yearlyCumulative.push({
        month: MONTH_NAMES[monthIndex - 1],
        fullMonth: FULL_MONTH_NAMES[monthIndex - 1],
        monthNumber: monthIndex,
        cumulative: yearCumulative + projectedRemainingEarnings,
        isProjected: true,
      });

      // Update cumulative for future months
      yearCumulative += projectedRemainingEarnings;
    } else if (isInFuture) {
      // Future months: project based on daily average
      const daysInMonth = new Date(Date.UTC(focusYear, monthIndex, 0)).getUTCDate();
      const projectedMonthEarnings = averageDailyEarnings * daysInMonth;
      yearCumulative += projectedMonthEarnings;
      yearlyCumulative.push({
        month: MONTH_NAMES[monthIndex - 1],
        fullMonth: FULL_MONTH_NAMES[monthIndex - 1],
        monthNumber: monthIndex,
        cumulative: yearCumulative,
        isProjected: true,
      });
    } else if (monthSummary) {
      // Past year, but has data
      yearCumulative += monthSummary.totalGross;
      yearlyCumulative.push({
        month: MONTH_NAMES[monthIndex - 1],
        fullMonth: FULL_MONTH_NAMES[monthIndex - 1],
        monthNumber: monthIndex,
        cumulative: yearCumulative,
        isProjected: false,
      });
    } else {
      // Past year, no data for this month
      yearlyCumulative.push({
        month: MONTH_NAMES[monthIndex - 1],
        fullMonth: FULL_MONTH_NAMES[monthIndex - 1],
        monthNumber: monthIndex,
        cumulative: yearCumulative,
        isProjected: false,
      });
    }
  }

  return {
    focusMonth: {
      year: focusYear,
      month: focusMonth,
    },
    tax: {
      enabled: taxEnabled,
      percentage: taxPercentage,
    },
    currentMonth: {
      totalEarnings: monthEarnings,
      totalEarningsNet: monthEarningsNet,
      totalHours: monthHours,
      shiftCount: monthShifts.length,
      averageRate: monthAvgRate,
    },
    lastMonth: {
      totalEarnings: lastMonthEarnings,
      totalEarningsNet: lastMonthEarningsNet,
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
    yearlyCumulative,
    monthlySummaries,
    currentMonthBreakdown: {
      basePay: +monthBasePay.toFixed(2),
      supplementPay: +monthSupplementPay.toFixed(2),
      basePercentage: +basePercentage.toFixed(1),
      supplementPercentage: +supplementPercentage.toFixed(1),
    },
    monthlyGoal: {
      enabled: monthlyGoalEnabled,
      target: monthlyGoalTarget,
      progress: +goalProgress.toFixed(2),
      percentage: +goalPercentage.toFixed(1),
      remaining: +goalRemaining.toFixed(2),
    },
  };
}

/**
 * Get comprehensive stats data with caching
 * - Uses React cache() for request deduplication
 * - Uses Next.js Data Cache for persistent caching (5 min TTL)
 * - Includes monthly summaries, charts data, and projections
 */
export const getStatsData = cache(async (userId: string, options: StatsOptions = {}): Promise<StatsData> => {
  // Resolve defaults to match internal implementation
  const { year: currentYear, month: currentMonth } = getCurrentYearMonth();
  const resolvedYear = options.year ?? currentYear;
  const resolvedMonth = options.month ?? currentMonth;

  const cacheKey = `stats-${userId}-${resolvedYear}-${resolvedMonth}`;

  const getCached = unstable_cache(
    async () => getStatsDataInternal(userId, options),
    [cacheKey],
    {
      tags: [`user-stats-${userId}`],
      revalidate: 300 // 5 minutes
    }
  );

  return getCached();
});

/**
 * Lightweight critical data type - only essential info for initial render
 */
export type CriticalStatsData = Pick<
  StatsData,
  | 'focusMonth'
  | 'tax'
  | 'currentMonth'
  | 'lastMonth'
  | 'percentageChange'
  | 'monthlyGoal'
>;

/**
 * Get only critical stats data for initial page render
 * - Loads only essential current month stats
 * - Much faster than full stats data
 * - Charts data loaded separately via API
 */
export const getCriticalStatsData = cache(async (
  userId: string,
  options: StatsOptions = {}
): Promise<CriticalStatsData> => {
  const fullData = await getStatsData(userId, options);

  // Return only critical fields needed for hero section
  return {
    focusMonth: fullData.focusMonth,
    tax: fullData.tax,
    currentMonth: fullData.currentMonth,
    lastMonth: fullData.lastMonth,
    percentageChange: fullData.percentageChange,
    monthlyGoal: fullData.monthlyGoal,
  };
});
