"use client";

import { useEffect, useMemo, useState, useRef, useCallback } from "react";
import type { ReactNode } from "react";
import dynamic from "next/dynamic";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/app/Card";
import type { StatsData } from "@/data-access/stats";
import { MonthlyGoalProgress } from "@/components/app/MonthlyGoalProgress";
import { TrendingUp, TrendingDown, Clock, Briefcase, DollarSign } from "lucide-react";
import { MonthPicker } from "@/components/app/MonthPicker";
import { YearPicker } from "@/components/app/YearPicker";
import { useMonth } from "@/components/app/MonthContext";
import { useTranslations } from "@/lib/i18n/client";
import { useParams } from "next/navigation";
import { formatNumber } from "@/lib/formatters";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";

/**
 * Chart data type - subset of StatsData used for chart components
 */
type ChartData = Pick<
  StatsData,
  | 'last6Months'
  | 'thisWeek'
  | 'thisMonthCumulative'
  | 'yearlyCumulative'
  | 'currentMonthBreakdown'
  | 'yearToDate'
  | 'employmentLast6Months'
  | 'employmentYearlyAverage'
>;

// Lazy load all chart components to reduce initial bundle size
const ChartSkeleton = () => (
  <div className="h-64 bg-surface-secondary rounded animate-pulse" />
);

const MonthlyBarChart = dynamic(
  () => import("@/components/app/charts/MonthlyBarChart").then(mod => mod.MonthlyBarChart),
  { loading: () => <ChartSkeleton /> }
);

const WeeklyBarChart = dynamic(
  () => import("@/components/app/charts/WeeklyBarChart").then(mod => mod.WeeklyBarChart),
  { loading: () => <ChartSkeleton /> }
);

const YearlyCumulativeChart = dynamic(
  () => import("@/components/app/charts/YearlyCumulativeChart").then(mod => mod.YearlyCumulativeChart),
  { loading: () => <ChartSkeleton /> }
);

const MonthlyCumulativeChart = dynamic(
  () => import("@/components/app/charts/MonthlyCumulativeChart").then(mod => mod.MonthlyCumulativeChart),
  { loading: () => <ChartSkeleton /> }
);

const SupplementBreakdownChart = dynamic(
  () => import("@/components/app/charts/SupplementBreakdownChart").then(mod => mod.SupplementBreakdownChart),
  { loading: () => <ChartSkeleton /> }
);

const EmploymentChart = dynamic(
  () => import("@/components/app/charts/EmploymentChart").then(mod => mod.EmploymentChart),
  { loading: () => <ChartSkeleton /> }
);

type StatsContentProps = {
  data: StatsData;
};

function formatHours(value: number): string {
  return formatNumber(value, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 1,
  });
}

type StatCardProps = {
  label: string;
  value: string;
  suffix?: string;
  trend?: {
    value: number;
    isPositive: boolean;
  };
  icon?: ReactNode;
};

function StatCard({ label, value, suffix, trend, icon }: StatCardProps) {
  const isZero = value === '0' || value === '0,0';
  const displayValue = isZero ? '---' : value;

  return (
    <Card className="border-border bg-surface-primary overflow-hidden">
      <CardContent className="p-5">
        <div className="flex items-start justify-between mb-3">
          <p className="text-base font-semibold text-text-muted">
            {label}
          </p>
          {icon && <div className="text-text-muted opacity-50">{icon}</div>}
        </div>
        <div className="flex items-baseline gap-1.5">
          <p className="text-3xl font-bold tabular-nums leading-none text-text-primary">
            {displayValue}
          </p>
          {suffix && !isZero && (
            <p className="text-xl font-medium shrink-0 text-text-secondary">
              {suffix}
            </p>
          )}
        </div>
        {trend && (
          <div className="flex items-center gap-1.5 mt-3">
            {trend.isPositive ? (
              <TrendingUp className="w-4 h-4 text-success" />
            ) : (
              <TrendingDown className="w-4 h-4 text-error" />
            )}
            <p className={`text-base font-medium ${trend.isPositive ? "text-success" : "text-error"}`}>
              {trend.isPositive ? "+" : ""}{trend.value}%
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export function StatsContent({ data }: StatsContentProps) {
  const { t } = useTranslations();
  const params = useParams();
  const locale = (params?.locale as string) || 'no';
  const formatCurrency = useFormatCurrency();
  // Format currency with full symbol (handles prefix/suffix positioning)
  const formatCurrencyFull = useCallback((value: number, compact = false): string => {
    if (compact && value >= 100000) {
      return formatCurrency(value, { notation: "compact" });
    }
    return formatCurrency(value);
  }, [formatCurrency]);
  const couldNotUpdateError = t.pages.stats.errors.couldNotUpdate;
  const {
    selectedMonth,
    setSelectedMonth,
    goToPreviousMonth,
    goToNextMonth,
    direction,
  } = useMonth();

  // Navigate to January of the previous year
  const goToPreviousYear = useCallback(() => {
    const previousYear = selectedMonth.getFullYear() - 1;
    setSelectedMonth(new Date(previousYear, 0, 1));
  }, [selectedMonth, setSelectedMonth]);

  // Navigate to January of the next year
  const goToNextYear = useCallback(() => {
    const nextYear = selectedMonth.getFullYear() + 1;
    setSelectedMonth(new Date(nextYear, 0, 1));
  }, [selectedMonth, setSelectedMonth]);

  const [activeData, setActiveData] = useState<StatsData>(data);
  // Initialize chart data from SSR props to avoid unnecessary skeleton UI
  const [chartData, setChartData] = useState<ChartData | null>({
    last6Months: data.last6Months,
    thisWeek: data.thisWeek,
    thisMonthCumulative: data.thisMonthCumulative,
    yearlyCumulative: data.yearlyCumulative,
    currentMonthBreakdown: data.currentMonthBreakdown,
    yearToDate: data.yearToDate,
    employmentLast6Months: data.employmentLast6Months,
    employmentYearlyAverage: data.employmentYearlyAverage,
  });
  const [isLoadingStats, setIsLoadingStats] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);

  // Prefetch cache: Map<"YYYY-MM", StatsData>
  const loadedMonthsData = useRef<Map<string, StatsData>>(new Map());

  // Swipe gesture refs
  const swipeContainerRef = useRef<HTMLDivElement>(null);
  const touchStartX = useRef<number | null>(null);
  const touchStartY = useRef<number | null>(null);
  const isSwiping = useRef<boolean>(false);
  const touchStartTarget = useRef<EventTarget | null>(null);

  const selectedYear = selectedMonth.getFullYear();
  const selectedMonthNumber = selectedMonth.getMonth() + 1;

  const focusYear = activeData.focusMonth.year;
  const focusMonth = activeData.focusMonth.month;

  // Fetch stats data for a given month
  const fetchStatsData = useCallback(
    async (year: number, month: number): Promise<StatsData | null> => {
      const monthKey = `${year}-${String(month).padStart(2, "0")}`;

      // Check cache first
      if (loadedMonthsData.current.has(monthKey)) {
        return loadedMonthsData.current.get(monthKey)!;
      }

      try {
        const query = new URLSearchParams({
          year: year.toString(),
          month: month.toString(),
          locale: locale,
        });

        const response = await fetch(`/api/stats?${query.toString()}`, {
          method: "GET",
          credentials: "include",
        });

        if (response.status === 401) {
          if (typeof window !== "undefined") {
            window.location.href = `/${locale}/login`;
          }
          throw new Error("Unauthorized");
        }

        if (!response.ok) {
          throw new Error(`Failed to load stats (${response.status})`);
        }

        const payload = (await response.json()) as StatsData;

        // Cache the result
        loadedMonthsData.current.set(monthKey, payload);
        return payload;
      } catch (error) {
        console.error(`Failed to fetch stats for ${monthKey}:`, error);
        return null;
      }
    },
    [locale]
  );

  // Handle month changes - load full stats data
  useEffect(() => {
    if (focusYear === selectedYear && focusMonth === selectedMonthNumber) {
      return;
    }

    const controller = new AbortController();
    const monthKey = `${selectedYear}-${String(selectedMonthNumber).padStart(2, "0")}`;

    // Check if data is already cached - if so, load immediately without showing loading state
    const cachedData = loadedMonthsData.current.get(monthKey);
    if (cachedData) {
      setActiveData(cachedData);
      setChartData({
        last6Months: cachedData.last6Months,
        thisWeek: cachedData.thisWeek,
        thisMonthCumulative: cachedData.thisMonthCumulative,
        yearlyCumulative: cachedData.yearlyCumulative,
        currentMonthBreakdown: cachedData.currentMonthBreakdown,
        yearToDate: cachedData.yearToDate,
        employmentLast6Months: cachedData.employmentLast6Months,
        employmentYearlyAverage: cachedData.employmentYearlyAverage,
      });
      return;
    }

    // Data not cached - show loading state and fetch
    setIsLoadingStats(true);
    setFetchError(null);

    fetchStatsData(selectedYear, selectedMonthNumber)
      .then((payload) => {
        if (controller.signal.aborted || !payload) {
          if (!payload && !controller.signal.aborted) {
            setFetchError(couldNotUpdateError);
          }
          return;
        }

        setActiveData(payload);
        // Extract chart data from full payload
        setChartData({
          last6Months: payload.last6Months,
          thisWeek: payload.thisWeek,
          thisMonthCumulative: payload.thisMonthCumulative,
          yearlyCumulative: payload.yearlyCumulative,
          currentMonthBreakdown: payload.currentMonthBreakdown,
          yearToDate: payload.yearToDate,
          employmentLast6Months: payload.employmentLast6Months,
          employmentYearlyAverage: payload.employmentYearlyAverage,
        });
      })
      .catch((error) => {
        if (controller.signal.aborted) {
          return;
        }
        console.error("Failed to load stats data", error);
        setFetchError(couldNotUpdateError);
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setIsLoadingStats(false);
        }
      });

    return () => {
      controller.abort();
    };
  }, [focusMonth, focusYear, selectedMonthNumber, selectedYear, fetchStatsData, couldNotUpdateError]);

  // Prefetch adjacent months for smooth swipe navigation (background only, no loading state)
  useEffect(() => {
    // Calculate previous and next month
    const prevDate = new Date(selectedYear, selectedMonthNumber - 2, 1);
    const nextDate = new Date(selectedYear, selectedMonthNumber, 1);

    const prevYear = prevDate.getFullYear();
    const prevMonthNum = prevDate.getMonth() + 1;

    const nextYear = nextDate.getFullYear();
    const nextMonthNum = nextDate.getMonth() + 1;

    // Prefetch only adjacent months in background (not current month - that's handled by main effect)
    Promise.all([
      fetchStatsData(prevYear, prevMonthNum),
      fetchStatsData(nextYear, nextMonthNum),
    ]).catch((error) => {
      console.error("Prefetch error:", error);
    });
  }, [selectedYear, selectedMonthNumber, fetchStatsData]);

  const grossEarnings = activeData.currentMonth.totalEarnings;
  const netEarnings = activeData.currentMonth.totalEarningsNet;
  const displayedEarnings = activeData.tax.enabled ? netEarnings : grossEarnings;
  const isEarningsZero = displayedEarnings === 0;

  const selectedHours = activeData.currentMonth.totalHours;
  const selectedShiftCount = activeData.currentMonth.shiftCount;
  const selectedAverageRate = activeData.currentMonth.averageRate;

  const trend = activeData.percentageChange !== null
    ? {
        value: activeData.percentageChange,
        isPositive: activeData.percentageChange >= 0,
      }
    : undefined;

  const realNow = useMemo(() => new Date(), []);
  const isCurrentMonthSelected =
    selectedYear === realNow.getUTCFullYear() &&
    selectedMonthNumber === realNow.getUTCMonth() + 1;

  // Helper function to check if touch started inside a chart
  const isInsideChart = (target: EventTarget | null): boolean => {
    if (!(target instanceof Element)) return false;
    // Check if the touch started inside a recharts container
    return target.closest('.recharts-wrapper') !== null;
  };

  // Swipe gesture detection for month navigation
  useEffect(() => {
    const container = swipeContainerRef.current;
    if (!container) return;

    const handleTouchStart = (e: TouchEvent) => {
      touchStartX.current = e.touches[0].clientX;
      touchStartY.current = e.touches[0].clientY;
      touchStartTarget.current = e.target;
      isSwiping.current = false;
    };

    const handleTouchMove = (e: TouchEvent) => {
      if (touchStartX.current === null || touchStartY.current === null) {
        return;
      }

      // Skip swipe detection if touch started inside a chart
      if (isInsideChart(touchStartTarget.current)) {
        return;
      }

      const deltaX = e.touches[0].clientX - touchStartX.current;
      const deltaY = e.touches[0].clientY - touchStartY.current;

      // Detect horizontal swipe and prevent default scroll behavior
      if (
        !isSwiping.current &&
        Math.abs(deltaX) > Math.abs(deltaY) &&
        Math.abs(deltaX) > 10
      ) {
        isSwiping.current = true;
      }

      if (isSwiping.current) {
        e.preventDefault();
      }
    };

    const handleTouchEnd = (e: TouchEvent) => {
      if (touchStartX.current === null || isLoadingStats) {
        touchStartX.current = null;
        touchStartY.current = null;
        touchStartTarget.current = null;
        isSwiping.current = false;
        return;
      }

      // Skip month navigation if touch started inside a chart
      if (!isInsideChart(touchStartTarget.current)) {
        const deltaX = e.changedTouches[0].clientX - touchStartX.current;
        const threshold = 50;

        if (Math.abs(deltaX) > threshold) {
          if (deltaX > 0) {
            // Swipe right -> previous month
            goToPreviousMonth();
          } else {
            // Swipe left -> next month
            goToNextMonth();
          }
        }
      }

      touchStartX.current = null;
      touchStartY.current = null;
      touchStartTarget.current = null;
      isSwiping.current = false;
    };

    container.addEventListener("touchstart", handleTouchStart, { passive: true });
    container.addEventListener("touchmove", handleTouchMove, { passive: false });
    container.addEventListener("touchend", handleTouchEnd, { passive: true });

    return () => {
      container.removeEventListener("touchstart", handleTouchStart);
      container.removeEventListener("touchmove", handleTouchMove);
      container.removeEventListener("touchend", handleTouchEnd);
    };
  }, [goToPreviousMonth, goToNextMonth, isLoadingStats]);

  // Determine animation class based on direction
  const animationClass =
    direction === "next"
      ? "animate-swipe-in-left"
      : direction === "previous"
        ? "animate-swipe-in-right"
        : "";

  return (
    <>
      {/* Loading indicator - subtle spinner next to month picker */}
      {isLoadingStats && (
        <div className="fixed top-4 right-4 z-50">
          <div className="w-5 h-5 border-2 border-brand-gradient-start border-t-transparent rounded-full animate-spin" />
        </div>
      )}

      <div
        ref={swipeContainerRef}
        className="w-full pb-6 pt-2 flex flex-col space-y-6 md:grid md:auto-rows-max md:gap-6 md:space-y-0"
        style={{
          gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 400px), 1fr))'
        }}
      >

      {/* Month picker - spans full width on desktop */}
      <div className="flex items-center justify-between mb-2 md:col-span-full">
        <MonthPicker
          month={selectedMonth}
          onPreviousMonth={goToPreviousMonth}
          onNextMonth={goToNextMonth}
        />
        <span className="font-medium text-text-muted mr-3">{selectedMonth.getFullYear()}</span>
      </div>

      {fetchError && (
        <p className="text-sm text-error md:col-span-full">
          {fetchError}
        </p>
      )}

      {/* Hero section with key metrics */}
      <div className={`space-y-5 ${animationClass}`}>
        <Card className="border-border bg-surface-primary overflow-hidden">
          <CardContent className="p-6">
            <p className="text-lg font-semibold text-text-muted mb-3">
              {t.pages.stats.cards.monthlyEarnings}
            </p>
            <p className="text-5xl font-bold tabular-nums text-text-primary">
              {isEarningsZero ? '---' : formatCurrencyFull(displayedEarnings, true)}
            </p>
            {activeData.tax.enabled && grossEarnings > 0 && (
              <div className="mt-3 space-y-1">
                <p className="text-base font-medium text-text-secondary">
                  {t.pages.stats.cards.afterTax}
                </p>
                <p className="text-sm text-text-muted">
                  {t.pages.stats.cards.beforeTax}: {formatCurrencyFull(grossEarnings, true)}
                </p>
              </div>
            )}
            {trend && (
              <div className="flex items-center gap-2 mt-4">
                {trend.isPositive ? (
                  <TrendingUp className="w-5 h-5 text-success" />
                ) : (
                  <TrendingDown className="w-5 h-5 text-error" />
                )}
                <p className={`text-lg font-medium ${trend.isPositive ? "text-success" : "text-error"}`}>
                  {trend.isPositive ? "+" : ""}{trend.value}% {t.pages.stats.cards.fromPreviousMonth}
                </p>
              </div>
            )}
          </CardContent>
        </Card>

        <div className="grid grid-cols-2 gap-3">
          <StatCard
            label={t.pages.stats.hours}
            value={formatHours(selectedHours)}
            icon={<Clock className="w-5 h-5" />}
          />
          <StatCard
            label={t.pages.stats.shifts}
            value={selectedShiftCount.toString()}
            icon={<Briefcase className="w-5 h-5" />}
          />
        </div>
      </div>

      {/* Monthly goal progress */}
      <div className={animationClass}>
        <MonthlyGoalProgress data={activeData.monthlyGoal} />
      </div>

      {/* Monthly cumulative comparison chart */}
      <Card className={`border-border bg-surface-primary ${animationClass}`}>
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            {t.pages.stats.cards.monthlyProgress}
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          {!chartData ? (
            <ChartSkeleton />
          ) : (
            <MonthlyCumulativeChart data={chartData.thisMonthCumulative} />
          )}
        </CardContent>
      </Card>

      {/* Supplement breakdown chart */}
      {selectedShiftCount > 0 && (
        <Card className={`border-border bg-surface-primary ${animationClass}`}>
          <CardHeader className="pb-3">
            <CardTitle className="text-xl font-bold text-text-primary">
              {t.pages.stats.cards.salaryComposition}
            </CardTitle>
          </CardHeader>
          <CardContent className="px-3 pb-4 pt-1">
            {!chartData ? (
              <ChartSkeleton />
            ) : (
              <SupplementBreakdownChart data={chartData.currentMonthBreakdown} />
            )}
          </CardContent>
        </Card>
      )}

      {/* Weekly earnings chart - only show for current month */}
      {isCurrentMonthSelected && (
        <Card className={`border-border bg-surface-primary ${animationClass}`}>
          <CardHeader className="pb-3">
            <CardTitle className="text-xl font-bold text-text-primary">
              {t.pages.stats.cards.thisWeek}
            </CardTitle>
          </CardHeader>
          <CardContent className="px-3 pb-4 pt-1">
            {!chartData ? (
              <ChartSkeleton />
            ) : (
              <WeeklyBarChart data={chartData.thisWeek} />
            )}
          </CardContent>
        </Card>
      )}

      {/* Average hourly rate */}
      <div className={animationClass}>
        <StatCard
          label={t.pages.stats.cards.average}
          value={formatCurrencyFull(selectedAverageRate, true)}
          suffix={t.common.perHour}
          icon={<DollarSign className="w-4 h-4" />}
        />
      </div>

      {/* Year to date summary header with year picker - spans full width on desktop */}
      <div className="flex items-center gap-2 md:col-span-full">
        <span className="text-xl font-bold text-text-primary pl-3">
          {t.pages.stats.cards.totalFor}
        </span>
        <YearPicker
          year={selectedYear}
          onPreviousYear={goToPreviousYear}
          onNextYear={goToNextYear}
        />
      </div>

      {/* Cumulative earnings chart */}
      <Card className={`border-border bg-surface-primary ${animationClass}`}>
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            {t.pages.stats.cards.cumulativeProgress}
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          {!chartData ? (
            <ChartSkeleton />
          ) : (
            <YearlyCumulativeChart data={chartData.yearlyCumulative} />
          )}
        </CardContent>
      </Card>

      <Card className={`border-border bg-surface-primary ${animationClass}`}>
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            {t.pages.stats.cards.last6Months}
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-4 pt-1">
          {!chartData ? (
            <ChartSkeleton />
          ) : (
            <MonthlyBarChart data={chartData.last6Months} />
          )}
        </CardContent>
      </Card>

      {/* Employment percentage chart */}
      <Card className={`border-border bg-surface-primary overflow-hidden ${animationClass}`}>
        <CardHeader className="pb-3">
          <CardTitle className="text-xl font-bold text-text-primary">
            {t.components.charts.employment.title}
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {!chartData ? (
            <ChartSkeleton />
          ) : (
            <EmploymentChart
              data={chartData.employmentLast6Months}
              yearlyAverage={chartData.employmentYearlyAverage}
              focusYear={focusYear}
            />
          )}
        </CardContent>
      </Card>

      {/* YTD stat cards - grouped together in one grid cell with internal grid */}
      <div className={`grid grid-cols-1 gap-3 ${animationClass}`}>
        {!chartData ? (
          <>
            <ChartSkeleton />
            <ChartSkeleton />
            <ChartSkeleton />
          </>
        ) : (
          <>
            <StatCard
              label={t.pages.stats.cards.total}
              value={formatCurrencyFull(chartData.yearToDate.totalEarnings)}
            />
            <StatCard
              label={t.pages.stats.hours}
              value={formatHours(chartData.yearToDate.totalHours)}
            />
            <StatCard
              label={t.pages.stats.shifts}
              value={chartData.yearToDate.shiftCount.toString()}
            />
          </>
        )}
      </div>
      </div>
    </>
  );
}
