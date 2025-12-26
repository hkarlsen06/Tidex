"use client";

import React, { useEffect, useMemo, useState, useRef, useCallback } from "react";
import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import { motion, useInView } from "framer-motion";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/app/Card";
import type { StatsData } from "@/data-access/stats";
import { MonthlyGoalProgress } from "@/components/app/MonthlyGoalProgress";
import { TrendingUp, TrendingDown, Clock, Briefcase } from "lucide-react";
import { MonthPicker } from "@/components/app/MonthPicker";
import { YearPicker } from "@/components/app/YearPicker";
import { useMonth } from "@/components/app/MonthContext";
import { useTranslations } from "@/lib/i18n/client";
import { useParams } from "next/navigation";
import { formatNumber } from "@/lib/formatters";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";
import { ScrollablePageWrapper } from "@/components/app/ScrollablePageWrapper";

// Scroll-triggered animation variants (slide in from left, out when leaving)
const scrollCardVariants = {
  hidden: { opacity: 0, x: -30 },
  visible: {
    opacity: 1,
    x: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
};

// Wrapper component that animates in AND out based on viewport visibility (mobile only)
const ScrollAnimatedCard = React.forwardRef<HTMLDivElement, { children: React.ReactNode; className?: string }>(
  function ScrollAnimatedCard({ children, className }, forwardedRef) {
    const internalRef = useRef<HTMLDivElement>(null);
    // Use larger top margin to account for navbar (~96px header + buffer)
    // Bottom margin for bottom navbar (~80px + buffer)
    const isInView = useInView(internalRef, { amount: 0.2, margin: "-120px 0px -100px 0px" });
    const [isDesktop, setIsDesktop] = useState(false);

    useEffect(() => {
      const checkDesktop = () => setIsDesktop(window.innerWidth >= 1024);
      checkDesktop();
      window.addEventListener('resize', checkDesktop);
      return () => window.removeEventListener('resize', checkDesktop);
    }, []);

    // Combine refs using a callback that avoids modifying the forwardedRef directly
    const setRefs = useCallback(
      (node: HTMLDivElement | null) => {
        // Set internal ref for useInView
        (internalRef as React.MutableRefObject<HTMLDivElement | null>).current = node;
        // Forward to external ref using React's imperative handle pattern
        if (typeof forwardedRef === 'function') {
          forwardedRef(node);
        } else if (forwardedRef) {
          // For RefObject, we need to use Object.assign to avoid direct mutation lint error
          Object.assign(forwardedRef, { current: node });
        }
      },
      [forwardedRef]
    );

    return (
      <motion.div
        ref={setRefs}
        className={className}
        variants={scrollCardVariants}
        initial={isDesktop ? "visible" : "hidden"}
        animate={isDesktop ? "visible" : (isInView ? "visible" : "hidden")}
      >
        {children}
      </motion.div>
    );
  }
);

/**
 * Chart data type - subset of StatsData used for chart components
 */
type ChartData = Pick<
  StatsData,
  | 'last6Months'
  | 'thisWeek'
  | 'bestWeek'
  | 'thisMonthCumulative'
  | 'yearlyCumulative'
  | 'currentMonthBreakdown'
  | 'yearToDate'
  | 'fullYear'
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
  secondaryValue?: string;
  secondaryLabel?: string;
};

function StatCard({ label, value, suffix, trend, icon, secondaryValue, secondaryLabel }: StatCardProps) {
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
        {secondaryValue && secondaryLabel && !isZero && (
          <p className="text-sm text-text-muted mt-2">
            {secondaryValue} {secondaryLabel}
          </p>
        )}
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
    isHydrated,
  } = useMonth();

  // Navigate to same month in previous year
  const goToPreviousYear = useCallback(() => {
    const previousYear = selectedMonth.getFullYear() - 1;
    const currentMonth = selectedMonth.getMonth();
    setSelectedMonth(new Date(previousYear, currentMonth, 1));
  }, [selectedMonth, setSelectedMonth]);

  // Navigate to same month in next year
  const goToNextYear = useCallback(() => {
    const nextYear = selectedMonth.getFullYear() + 1;
    const currentMonth = selectedMonth.getMonth();
    setSelectedMonth(new Date(nextYear, currentMonth, 1));
  }, [selectedMonth, setSelectedMonth]);

  const [activeData, setActiveData] = useState<StatsData>(data);
  // Initialize chart data from SSR props to avoid unnecessary skeleton UI
  const [chartData, setChartData] = useState<ChartData | null>({
    last6Months: data.last6Months,
    thisWeek: data.thisWeek,
    bestWeek: data.bestWeek,
    thisMonthCumulative: data.thisMonthCumulative,
    yearlyCumulative: data.yearlyCumulative,
    currentMonthBreakdown: data.currentMonthBreakdown,
    yearToDate: data.yearToDate,
    fullYear: data.fullYear,
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

  // Get month name for the year picker suffix
  const selectedMonthName = t.dateTime.monthsShort[selectedMonth.getMonth()];
  const yearPickerSuffix = `${t.pages.stats.cards.upTo} ${selectedMonthName.toLowerCase()}`;

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
        bestWeek: cachedData.bestWeek,
        thisMonthCumulative: cachedData.thisMonthCumulative,
        yearlyCumulative: cachedData.yearlyCumulative,
        currentMonthBreakdown: cachedData.currentMonthBreakdown,
        yearToDate: cachedData.yearToDate,
        fullYear: cachedData.fullYear,
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
          bestWeek: payload.bestWeek,
          thisMonthCumulative: payload.thisMonthCumulative,
          yearlyCumulative: payload.yearlyCumulative,
          currentMonthBreakdown: payload.currentMonthBreakdown,
          yearToDate: payload.yearToDate,
          fullYear: payload.fullYear,
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
      // Require more intentional horizontal gesture: deltaX must be 2x deltaY and > 25px
      if (
        !isSwiping.current &&
        Math.abs(deltaX) > Math.abs(deltaY) * 2 &&
        Math.abs(deltaX) > 25
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
        // Higher threshold (80px) to reduce accidental swipes on stats page
        const threshold = 80;

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
    <ScrollablePageWrapper routeKey="stats" applyContainer={false}>
      {/* Loading indicator - subtle spinner next to month picker */}
      {isLoadingStats && (
        <div className="fixed top-4 right-4 z-50">
          <div className="w-5 h-5 border-2 border-brand-gradient-start border-t-transparent rounded-full animate-spin" />
        </div>
      )}

      <div
        ref={swipeContainerRef}
        className="w-full pb-6 pt-2 px-4 flex flex-col space-y-6 md:grid md:grid-cols-2 md:gap-6 md:space-y-0 md:items-start"
      >

      {/* Month picker - left column header */}
      <div className="flex items-center justify-between mb-2 md:mb-0 md:h-10">
        <MonthPicker
          month={selectedMonth}
          onPreviousMonth={goToPreviousMonth}
          onNextMonth={goToNextMonth}
          direction={direction === 'next' ? 'forward' : direction === 'previous' ? 'backward' : undefined}
          isHydrated={isHydrated}
        />
        <span className="font-medium text-text-muted mr-3 md:hidden">{selectedMonth.getFullYear()}</span>
      </div>

      {/* Year picker - right column header */}
      <div className="hidden md:flex items-center h-10">
        <YearPicker
          year={selectedYear}
          onPreviousYear={goToPreviousYear}
          onNextYear={goToNextYear}
          suffix={yearPickerSuffix}
        />
      </div>

      {fetchError && (
        <p className="text-sm text-error md:col-span-2">
          {fetchError}
        </p>
      )}

      {/* LEFT COLUMN - Monthly stats */}
      <div className="flex flex-col space-y-6">
        {/* Hero section with key metrics */}
        <ScrollAnimatedCard className={`space-y-5 ${animationClass}`}>
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
        </ScrollAnimatedCard>

        {/* Monthly goal progress */}
        <ScrollAnimatedCard className={animationClass}>
          <MonthlyGoalProgress data={activeData.monthlyGoal} />
        </ScrollAnimatedCard>

        {/* Monthly cumulative comparison chart */}
        <ScrollAnimatedCard>
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
        </ScrollAnimatedCard>

        {/* Supplement breakdown chart */}
        {selectedShiftCount > 0 && (
          <ScrollAnimatedCard>
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
          </ScrollAnimatedCard>
        )}

        {/* Weekly earnings chart - "This week" for current month, "Best week" for past months */}
        {isCurrentMonthSelected ? (
          <ScrollAnimatedCard>
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
          </ScrollAnimatedCard>
        ) : chartData?.bestWeek && (
          <ScrollAnimatedCard>
            <Card className={`border-border bg-surface-primary ${animationClass}`}>
              <CardHeader className="pb-3">
                <CardTitle className="text-xl font-bold text-text-primary">
                  {`${t.pages.stats.cards.bestWeek} (${t.pages.stats.cards.week} ${chartData.bestWeek.weekNumber})`}
                </CardTitle>
              </CardHeader>
              <CardContent className="px-3 pb-4 pt-1">
                <WeeklyBarChart data={chartData.bestWeek.weekData} highlightBestDay showDatesInsteadOfDays />
              </CardContent>
            </Card>
          </ScrollAnimatedCard>
        )}
      </div>

      {/* RIGHT COLUMN - Yearly stats */}
      <div className="flex flex-col space-y-6">
        {/* Year picker - mobile only (shown in header on desktop) */}
        <ScrollAnimatedCard className="flex items-center gap-2 md:hidden">
          <YearPicker
            year={selectedYear}
            onPreviousYear={goToPreviousYear}
            onNextYear={goToNextYear}
            suffix={yearPickerSuffix}
          />
        </ScrollAnimatedCard>

        {/* YTD stat cards */}
        <ScrollAnimatedCard className={`space-y-3 ${animationClass}`}>
          {!chartData ? (
            <>
              <ChartSkeleton />
              <div className="grid grid-cols-2 gap-3">
                <ChartSkeleton />
                <ChartSkeleton />
              </div>
            </>
          ) : (
            <>
              <StatCard
                label={t.pages.stats.cards.total}
                value={formatCurrencyFull(chartData.yearToDate.totalEarnings)}
                secondaryValue={formatCurrencyFull(chartData.fullYear.totalEarnings)}
                secondaryLabel={t.pages.stats.cards.forFullYear}
              />
              <div className="grid grid-cols-2 gap-3">
                <StatCard
                  label={t.pages.stats.hours}
                  value={formatHours(chartData.yearToDate.totalHours)}
                  icon={<Clock className="w-5 h-5" />}
                  secondaryValue={formatHours(chartData.fullYear.totalHours)}
                  secondaryLabel={t.pages.stats.cards.forFullYear}
                />
                <StatCard
                  label={t.pages.stats.shifts}
                  value={chartData.yearToDate.shiftCount.toString()}
                  icon={<Briefcase className="w-5 h-5" />}
                  secondaryValue={chartData.fullYear.shiftCount.toString()}
                  secondaryLabel={t.pages.stats.cards.forFullYear}
                />
              </div>
            </>
          )}
        </ScrollAnimatedCard>

        {/* Cumulative earnings chart */}
        <ScrollAnimatedCard>
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
        </ScrollAnimatedCard>

        {/* Monthly earnings chart */}
        <ScrollAnimatedCard>
          <Card className={`border-border bg-surface-primary ${animationClass}`}>
            <CardHeader className="pb-3">
              <CardTitle className="text-xl font-bold text-text-primary">
                {t.pages.stats.cards.yearlyBreakdown} {focusYear}
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
        </ScrollAnimatedCard>

        {/* Employment percentage chart */}
        <ScrollAnimatedCard>
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
        </ScrollAnimatedCard>
      </div>
      </div>
    </ScrollablePageWrapper>
  );
}
