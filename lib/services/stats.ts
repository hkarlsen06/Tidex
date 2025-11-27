/**
 * Stats Service Layer
 *
 * Effect-based service for statistics and analytics with:
 * - Monthly and yearly aggregations
 * - Chart data computation
 * - Projections and trends
 * - Type-safe error handling
 *
 * Usage:
 * ```typescript
 * const program = Effect.gen(function* () {
 *   const stats = yield* StatsService
 *   const data = yield* stats.getStatsData({
 *     userId,
 *     year: 2025,
 *     month: 1,
 *     locale: "no"
 *   })
 *   return data
 * }).pipe(
 *   Effect.provide(StatsServiceLive)
 * )
 * ```
 */

import "server-only";
import { Context, Effect, Layer } from "effect";
import { ShiftsService } from "./shifts";
import { SettingsService, type DbUserSettings } from "./settings";
import { DatabaseError, AuthError, NotFoundError, TimeoutError, SupabaseError } from "../errors/tagged";
import type { ShiftWithComputations } from "../payroll";
import {
  getCurrentYearMonth,
  getPreviousYearMonth,
  getMonthStart,
  getMonthEnd,
  isDateInMonth,
  parseDateAsUTC,
  getYearMonth,
  getCurrentYearStart,
  getCurrentYearEnd,
} from "../date-utils";
import type { Locale } from "../i18n/config";
import { getTranslations } from "../i18n/server";
import { formatCurrency } from "../formatters";
import { getMonthlyTotals } from "../shifts/monthlyTotals";

/**
 * Monthly data aggregation
 */
export type MonthlyData = {
  month: string; // "Jan", "Feb", etc.
  fullMonth: string; // "Januar", "Februar", etc.
  earnings: number;
  hours: number;
  shifts: number;
  year: number;
  monthNumber: number; // 1-12
};

/**
 * Daily data aggregation
 */
export type DailyData = {
  date: string; // "Mon", "Tue", etc. or full date
  fullDay: string; // "Mandag", "Tirsdag", etc.
  earnings: number;
  hours: number;
  shifts: number;
  fullDate: string; // YYYY-MM-DD
};

/**
 * Daily cumulative comparison data
 */
export type DailyCumulativeData = {
  day: string; // "1", "2", "3", etc.
  dayNumber: number; // 1-31
  currentMonth: number; // Cumulative earnings for current month
  lastMonth: number; // Cumulative earnings for last month (same day)
  isToday: boolean;
  isFuture: boolean;
};

/**
 * Yearly cumulative data with projection
 */
export type YearlyCumulativeData = {
  month: string; // "Jan", "Feb", etc.
  fullMonth: string; // "Januar", "Februar", etc.
  monthNumber: number; // 1-12
  cumulative: number; // Cumulative earnings up to this month
  isProjected: boolean; // Whether this is a projected value
};

/**
 * Monthly summary for aggregations
 */
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

/**
 * Supplement pay breakdown
 */
export type SupplementBreakdown = {
  readonly basePay: number;
  readonly supplementPay: number;
  readonly basePercentage: number;
  readonly supplementPercentage: number;
};

/**
 * Monthly goal tracking
 */
export type MonthlyGoal = {
  readonly enabled: boolean;
  readonly target: number;
  readonly progress: number; // current earnings
  readonly percentage: number; // progress as % of goal
  readonly remaining: number; // amount left to reach goal
};

/**
 * Employment percentage data for a month
 */
export type EmploymentMonthlyData = {
  readonly month: string; // "Jan", "Feb", etc.
  readonly fullMonth: string; // "Januar", "Februar", etc.
  readonly year: number;
  readonly monthNumber: number; // 1-12
  readonly averagePercentage: number; // Average employment percentage for the month
  readonly hasShifts: boolean; // Whether the month has any shifts
};

/**
 * Complete stats data response
 */
export type StatsData = {
  readonly focusMonth: {
    readonly year: number;
    readonly month: number;
  };
  readonly tax: {
    readonly enabled: boolean;
    readonly percentage: number;
  };
  readonly currentMonth: {
    readonly totalEarnings: number;
    readonly totalEarningsNet: number;
    readonly totalHours: number;
    readonly shiftCount: number;
    readonly averageRate: number;
  };
  readonly lastMonth: {
    readonly totalEarnings: number;
    readonly totalEarningsNet: number;
    readonly totalHours: number;
    readonly shiftCount: number;
  };
  readonly percentageChange: number | null;
  readonly yearToDate: {
    readonly totalEarnings: number;
    readonly totalHours: number;
    readonly shiftCount: number;
  };
  readonly last6Months: MonthlyData[];
  readonly thisWeek: DailyData[];
  readonly thisMonthCumulative: DailyCumulativeData[];
  readonly yearlyCumulative: YearlyCumulativeData[];
  readonly monthlySummaries: MonthlySummary[];
  readonly currentMonthBreakdown: SupplementBreakdown;
  readonly monthlyGoal: MonthlyGoal;
  readonly employmentLast6Months: EmploymentMonthlyData[];
  readonly employmentYearlyAverage: number | null; // null if no months with shifts
};

/**
 * Monthly total summary
 */
export type MonthlyTotal = {
  readonly total: string;
  readonly percentageChange?: number | "..";
  readonly tillegg: string;
  readonly gross: number;
  readonly supplementPay: number;
  readonly shiftCount: number;
  readonly earnedToDate: string;
  readonly earnedToDateGross: number;
};

/**
 * Stats query options
 */
export type StatsOptions = {
  readonly userId: string;
  readonly year?: number;
  readonly month?: number; // 1-12
  readonly locale?: Locale;
};

/**
 * Critical stats data (lightweight for initial render)
 */
export type CriticalStatsData = Pick<
  StatsData,
  | "focusMonth"
  | "tax"
  | "currentMonth"
  | "lastMonth"
  | "percentageChange"
  | "monthlyGoal"
>;

/**
 * Stats Service Interface
 */
export class StatsService extends Context.Tag("StatsService")<
  StatsService,
  {
    /**
     * Get monthly total with comparison to last month
     */
    readonly getMonthlyTotal: (
      userId: string
    ) => Effect.Effect<
      MonthlyTotal,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get comprehensive stats data with all aggregations and charts
     */
    readonly getStatsData: (
      options: StatsOptions
    ) => Effect.Effect<
      StatsData,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get critical stats data only (lightweight)
     * Returns only essential data for initial render
     */
    readonly getCriticalStatsData: (
      options: StatsOptions
    ) => Effect.Effect<
      CriticalStatsData,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;
  }
>() {}

/**
 * Live implementation of StatsService
 *
 * Provides comprehensive statistics and analytics with projections
 */
export const StatsServiceLive = Layer.effect(
  StatsService,
  Effect.gen(function* () {
    const shifts = yield* ShiftsService;

    /**
     * Get date range for stats based on target year and month
     * Includes previous year months needed for "last 6 months" charts
     */
    const getStatsDateRange = (options: StatsOptions): { startDate: string; endDate: string } => {
      const { year: currentYear, month: currentMonth } = getCurrentYearMonth();
      const targetYear = options.year ?? currentYear;
      const targetMonth = options.month ?? currentMonth;

      // Calculate the earliest month needed (5 months before target month)
      // This is needed for the "last 6 months" charts
      const earliestDate = new Date(Date.UTC(targetYear, targetMonth - 1 - 5, 1));
      const earliestYear = earliestDate.getUTCFullYear();
      const earliestMonth = earliestDate.getUTCMonth() + 1;

      // Start date: first day of the earliest month needed
      const startDate = `${earliestYear}-${String(earliestMonth).padStart(2, "0")}-01`;

      // End date: last day of target year
      const endDate = `${targetYear}-12-31`;

      return { startDate, endDate };
    };

    /**
     * Get monthly total with comparison
     */
    const getMonthlyTotal = (userId: string) =>
      Effect.gen(function* () {
        // Load current month + previous month only (2 months total)
        const { year, month } = getCurrentYearMonth();
        const { year: prevYear, month: prevMonth } = getPreviousYearMonth();

        const shiftData = yield* shifts.getShiftsWithComputations({
          userId,
          startDate: getMonthStart(prevYear, prevMonth),
          endDate: getMonthEnd(year, month),
          limit: 100, // Reasonable limit for 2 months
        });

        const allShifts = shiftData.shifts;

        // Get current month and year in UTC to ensure consistent date comparisons
        const { year: currentYear, month: currentMonth } = getCurrentYearMonth();
        const { year: lastMonthYear, month: lastMonth } = getPreviousYearMonth();

        // Filter shifts for current month
        const currentMonthTotals = getMonthlyTotals({
          shifts: allShifts as ShiftWithComputations[],
          year: currentYear,
          month: currentMonth,
        });

        const lastMonthTotals = getMonthlyTotals({
          shifts: allShifts as ShiftWithComputations[],
          year: lastMonthYear,
          month: lastMonth,
        });

        const gross = currentMonthTotals.gross;
        const supplementPay = currentMonthTotals.supplement;
        const earnedToDateGross = currentMonthTotals.completedGross;
        const lastMonthGross = lastMonthTotals.gross;

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
          shiftCount: currentMonthTotals.shiftCount,
          earnedToDate: formatCurrency(earnedToDateGross),
          earnedToDateGross,
        } as MonthlyTotal;
      });

    /**
     * Get comprehensive stats data
     */
    const getStatsData = (options: StatsOptions) =>
      Effect.gen(function* () {
        const { userId, locale = "no" } = options;

        // Get translations for month/day names
        const t = getTranslations(locale);
        const MONTH_NAMES = t.dateTime.monthsShort;
        const FULL_MONTH_NAMES = t.dateTime.monthsFull;
        const DAY_NAMES = t.dateTime.daysShort;
        const FULL_DAY_NAMES = t.dateTime.daysFull;

        // Load full year of shifts for comprehensive stats calculations
        const dateRange = getStatsDateRange(options);
        const shiftData = yield* shifts.getShiftsWithComputations({
          userId,
          ...dateRange,
          limit: 1000, // Reasonable limit for 1 year of data
        });

        const allShifts = shiftData.shifts;
        const userSettings = shiftData.settings;

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

        const taxEnabled = (userSettings as DbUserSettings).tax_deduction_enabled ?? false;
        const taxPercentage = taxEnabled ? Number((userSettings as DbUserSettings).tax_percentage ?? 0) : 0;
        const netMultiplier = taxEnabled ? 1 - taxPercentage / 100 : 1;
        const applyNet = (gross: number) => (taxEnabled ? +(gross * netMultiplier).toFixed(2) : gross);

        // Pre-compute monthly aggregates for client-side month switching
        const monthlyMap = new Map<string, MonthlySummary>();

        for (const shift of allShifts) {
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

          monthlyMap.set(key, {
            key,
            year,
            month: monthIndex,
            totalGross: existing.totalGross + gross,
            totalNet: existing.totalNet + (taxEnabled ? gross * netMultiplier : gross),
            totalHours: existing.totalHours + hours,
            shiftCount: existing.shiftCount + 1,
            averageRate: 0, // Will be calculated below
          });
        }

        const monthlySummaries = Array.from(monthlyMap.values())
          .map((summary) => {
            const totalGross = +summary.totalGross.toFixed(2);
            const totalNet = +summary.totalNet.toFixed(2);
            const totalHours = +summary.totalHours.toFixed(2);
            const averageRate = totalHours > 0 ? +(totalGross / totalHours).toFixed(2) : 0;

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
        const monthShifts = allShifts.filter((shift) => isDateInMonth(shift.shift_date, focusYear, focusMonth));
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
        const monthlyGoalTarget = (userSettings as DbUserSettings).monthly_goal
          ? Number((userSettings as DbUserSettings).monthly_goal)
          : 0;
        const monthlyGoalEnabled = monthlyGoalTarget > 0;
        const goalProgress = taxEnabled ? monthEarningsNet : monthEarnings;
        const goalPercentage = monthlyGoalEnabled ? (goalProgress / monthlyGoalTarget) * 100 : 0;
        const goalRemaining = monthlyGoalEnabled ? Math.max(0, monthlyGoalTarget - goalProgress) : 0;

        // Last month stats
        const lastMonthShifts = allShifts.filter((shift) => isDateInMonth(shift.shift_date, lastMonthYear, lastMonth));
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
        const ytdShifts = allShifts.filter((shift) => {
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

          const monthShifts = allShifts.filter((shift) => isDateInMonth(shift.shift_date, year, month));
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
        const currentDayOfWeek = realNow.getUTCDay();
        // Calculate days since Monday (treat Sunday as 7)
        const daysSinceMonday = currentDayOfWeek === 0 ? 6 : currentDayOfWeek - 1;

        // Start from Monday of the current week
        for (let i = 0; i < 7; i++) {
          const daysFromMonday = i - daysSinceMonday;
          const targetDate = new Date(
            Date.UTC(realNow.getUTCFullYear(), realNow.getUTCMonth(), realNow.getUTCDate() + daysFromMonday)
          );
          const dateString = targetDate.toISOString().split("T")[0];

          // Find shifts for this day from ALL shifts
          const dayShifts = allShifts.filter((shift) => shift.shift_date === dateString);
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
          const currentDayDate = new Date(Date.UTC(focusYear, focusMonth - 1, day)).toISOString().split("T")[0];
          const currentDayShifts = allShifts.filter((shift) => shift.shift_date === currentDayDate);
          const currentDayEarnings = currentDayShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
          currentMonthCumulative += currentDayEarnings;

          // Last month - check if there are shifts on this day (if it exists in last month)
          const lastMonthDate = new Date(Date.UTC(lastMonthYear, lastMonth - 1, day));
          const daysInLastMonth = new Date(Date.UTC(lastMonthYear, lastMonth, 0)).getUTCDate();

          if (day <= daysInLastMonth) {
            const lastDayDate = lastMonthDate.toISOString().split("T")[0];
            const lastDayShifts = allShifts.filter((shift) => shift.shift_date === lastDayDate);
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

        // Calculate employment percentage data
        // Full-time hours per week: 37.5 if pause deduction enabled, 40 otherwise
        const fullTimeHoursPerWeek = (userSettings as DbUserSettings).pause_deduction_enabled ? 37.5 : 40;

        // Helper to get Monday of a week containing a date
        const getMondayOfWeek = (date: Date): Date => {
          const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
          const day = d.getUTCDay();
          const diff = day === 0 ? -6 : 1 - day; // Sunday = 0, Monday = 1
          d.setUTCDate(d.getUTCDate() + diff);
          return d;
        };

        // Helper to get date string YYYY-MM-DD
        const toDateString = (date: Date): string => date.toISOString().split("T")[0];

        // Build a map of date -> hours worked
        const hoursPerDay = new Map<string, number>();
        for (const shift of allShifts) {
          const dateStr = shift.shift_date;
          const hours = shift.computed.paidHours || 0;
          hoursPerDay.set(dateStr, (hoursPerDay.get(dateStr) || 0) + hours);
        }

        // Calculate employment percentages for all weeks in the focus year
        // and accumulate into monthly data
        type MonthAccumulator = {
          totalWeightedPercentage: number;
          totalWeight: number;
          hasShifts: boolean;
        };
        const monthlyEmployment = new Map<string, MonthAccumulator>();

        // Initialize all 12 months for the focus year
        for (let m = 1; m <= 12; m++) {
          const key = `${focusYear}-${String(m).padStart(2, "0")}`;
          monthlyEmployment.set(key, { totalWeightedPercentage: 0, totalWeight: 0, hasShifts: false });
        }

        // Also initialize months from the previous year that fall within the last 6 months range
        // This is needed when focusMonth is Jan-May (e.g., Jan 2025 needs Jul-Dec 2024)
        for (let i = 5; i >= 0; i--) {
          const targetDate = new Date(Date.UTC(focusYear, focusMonth - 1 - i, 1));
          const { year, month } = getYearMonth(targetDate);
          if (year < focusYear) {
            const key = `${year}-${String(month).padStart(2, "0")}`;
            if (!monthlyEmployment.has(key)) {
              monthlyEmployment.set(key, { totalWeightedPercentage: 0, totalWeight: 0, hasShifts: false });
            }
          }
        }

        // Determine the earliest year we need to process for employment data
        const earliestTargetDate = new Date(Date.UTC(focusYear, focusMonth - 1 - 5, 1));
        const earliestYear = earliestTargetDate.getUTCFullYear();

        // Find the first Monday of the earliest year we need
        const processStartYear = new Date(Date.UTC(earliestYear, 0, 1));
        let currentMonday = getMondayOfWeek(processStartYear);

        // Process all weeks until we pass the end of the focus year
        const yearEnd = new Date(Date.UTC(focusYear, 11, 31));

        while (currentMonday <= yearEnd) {
          const weekDays: Date[] = [];
          for (let i = 0; i < 7; i++) {
            const day = new Date(currentMonday);
            day.setUTCDate(day.getUTCDate() + i);
            weekDays.push(day);
          }

          // Calculate total hours worked this week
          let totalWeekHours = 0;
          for (const day of weekDays) {
            const dateStr = toDateString(day);
            totalWeekHours += hoursPerDay.get(dateStr) || 0;
          }

          // Calculate employment percentage for this week
          const weekEmploymentPct = (totalWeekHours / fullTimeHoursPerWeek) * 100;

          // Distribute this week's percentage to months based on how many days fall in each month
          const daysPerMonth = new Map<string, number>();
          for (const day of weekDays) {
            // Only count days in months we're tracking (focus year + any previous year months in our range)
            const monthKey = `${day.getUTCFullYear()}-${String(day.getUTCMonth() + 1).padStart(2, "0")}`;
            if (monthlyEmployment.has(monthKey)) {
              daysPerMonth.set(monthKey, (daysPerMonth.get(monthKey) || 0) + 1);
            }
          }

          // Add weighted contribution to each month
          for (const [monthKey, dayCount] of daysPerMonth) {
            const weight = dayCount / 7; // Proportion of the week in this month
            const monthData = monthlyEmployment.get(monthKey);
            if (monthData) {
              monthData.totalWeightedPercentage += weekEmploymentPct * weight;
              monthData.totalWeight += weight;
              // Check if any hours were worked on days in this month
              for (const day of weekDays) {
                const dayMonthKey = `${day.getUTCFullYear()}-${String(day.getUTCMonth() + 1).padStart(2, "0")}`;
                if (dayMonthKey === monthKey) {
                  const dateStr = toDateString(day);
                  if ((hoursPerDay.get(dateStr) || 0) > 0) {
                    monthData.hasShifts = true;
                  }
                }
              }
            }
          }

          // Move to next week
          currentMonday.setUTCDate(currentMonday.getUTCDate() + 7);
        }

        // Build employment data for a wider window (6 months before + 5 months after focus month)
        // This allows the frontend to shift the 6-month window forward if there are leading zeros
        const employmentLast6Months: EmploymentMonthlyData[] = [];
        for (let i = 5; i >= -5; i--) {
          const targetDate = new Date(Date.UTC(focusYear, focusMonth - 1 - i, 1));
          const { year, month } = getYearMonth(targetDate);
          const monthKey = `${year}-${String(month).padStart(2, "0")}`;
          const monthData = monthlyEmployment.get(monthKey);

          const averagePercentage = monthData && monthData.totalWeight > 0
            ? monthData.totalWeightedPercentage / monthData.totalWeight
            : 0;

          employmentLast6Months.push({
            month: MONTH_NAMES[month - 1],
            fullMonth: FULL_MONTH_NAMES[month - 1],
            year,
            monthNumber: month,
            averagePercentage: +averagePercentage.toFixed(1),
            hasShifts: monthData?.hasShifts ?? false,
          });
        }

        // Calculate yearly average (only months with shifts)
        let yearlySum = 0;
        let monthsWithShifts = 0;
        for (const [, monthData] of monthlyEmployment) {
          if (monthData.hasShifts && monthData.totalWeight > 0) {
            const monthAvg = monthData.totalWeightedPercentage / monthData.totalWeight;
            yearlySum += monthAvg;
            monthsWithShifts++;
          }
        }
        const employmentYearlyAverage = monthsWithShifts > 0
          ? +(yearlySum / monthsWithShifts).toFixed(1)
          : null;

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
          last6Months: last6Months as readonly MonthlyData[],
          thisWeek: thisWeek as readonly DailyData[],
          thisMonthCumulative: thisMonthCumulative as readonly DailyCumulativeData[],
          yearlyCumulative: yearlyCumulative as readonly YearlyCumulativeData[],
          monthlySummaries: monthlySummaries as readonly MonthlySummary[],
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
          employmentLast6Months: employmentLast6Months as readonly EmploymentMonthlyData[],
          employmentYearlyAverage,
        } as StatsData;
      });

    /**
     * Get critical stats data only
     */
    const getCriticalStatsData = (options: StatsOptions) =>
      Effect.gen(function* () {
        const fullData = yield* getStatsData(options);

        // Return only critical fields needed for hero section
        return {
          focusMonth: fullData.focusMonth,
          tax: fullData.tax,
          currentMonth: fullData.currentMonth,
          lastMonth: fullData.lastMonth,
          percentageChange: fullData.percentageChange,
          monthlyGoal: fullData.monthlyGoal,
        } as CriticalStatsData;
      });

    return {
      getMonthlyTotal,
      getStatsData,
      getCriticalStatsData,
    };
  })
);

/**
 * Convenience function to provide StatsServiceLive with dependencies
 */
export const withStats = <A, E, R>(
  effect: Effect.Effect<A, E, R | StatsService>
): Effect.Effect<A, E, Exclude<R, StatsService> | ShiftsService | SettingsService> =>
  Effect.provide(effect, StatsServiceLive);
