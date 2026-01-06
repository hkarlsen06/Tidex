"use client";

import { useState, useMemo, useEffect, useCallback, useTransition, useRef } from "react";
import { useRouter } from "next/navigation";
import { TotalCard } from "@/components/app/TotalCard";
import { NextPayrollCard } from "@/components/app/NextPayrollCard";
import { MonthPicker } from "./MonthPicker";
import { ShiftCard } from "@/components/app/ShiftCard";
import { ShiftCardSkeleton } from "@/components/app/skeletons";
import ShiftDetails from "@/components/shifts/ShiftDetails";
import { ShiftWithComputations, UserSettings, computeShift, PRESET_SUPPLEMENT_RULES } from "@/lib/payroll";
import { useCountdown } from "@/lib/hooks/useCountdown";
import { usePayrollCountdown } from "@/lib/hooks/usePayrollCountdown";
import { useMonth } from "./MonthContext";
import { useTranslations } from "@/lib/i18n/client";
import { summarizeShiftTotals } from "@/lib/shifts/monthlyTotals";
import { hasShiftEnded } from "@/lib/shifts/hasShiftEnded";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";
import { adjustPayrollDate } from "@/lib/payroll/adjust-payroll-date";
import { useSwipe } from "@/lib/hooks/useSwipe";
import { CenteredPageWrapper } from "./CenteredPageWrapper";
import type { PayoutTaxSettings } from "@/data-access/shifts";

type HomeContentProps = {
  shifts: ShiftWithComputations[];
  settings: UserSettings;
  /** Tax settings for current month's earnings (paid next month) - used for TotalCard */
  payoutTaxSettings?: PayoutTaxSettings;
  /** Tax settings for previous month's earnings (paid this month) - used for NextPayrollCard */
  currentPayoutTaxSettings?: PayoutTaxSettings;
  /** User-specific cache key to ensure browser HTTP cache is per-user */
  cacheKey: string;
  /** Months that were preloaded in SSR (format: "YYYY-MM") */
  preloadedMonths?: string[];
};

function calculateMonthData(
  shiftsByMonth: Map<string, ShiftWithComputations[]>,
  month: Date,
  settings: UserSettings,
  formatCurrency: (value: number) => string,
  payoutTaxSettings?: PayoutTaxSettings
): {
  total: string;
  percentageChange?: number;
  projectedTotal: string;
  grossBeforeTax?: string;
  projectedGrossBeforeTax?: string;
} {
  const targetYear = month.getFullYear();
  const targetMonth = month.getMonth() + 1;

  // O(1) lookup instead of O(n) filtering
  const targetYearMonth = `${targetYear}-${String(targetMonth).padStart(2, '0')}`;
  const currentMonthShifts = shiftsByMonth.get(targetYearMonth) || [];

  // O(1) lookup for last month
  const lastMonthDate = new Date(targetYear, targetMonth - 2, 1);
  const lastMonthYear = lastMonthDate.getFullYear();
  const lastMonth = lastMonthDate.getMonth() + 1;
  const lastMonthKey = `${lastMonthYear}-${String(lastMonth).padStart(2, '0')}`;
  const lastMonthShifts = shiftsByMonth.get(lastMonthKey) || [];

  // Tax settings are now per-shift, but half_tax_month is still global
  const halfTaxMonth = settings.half_tax_month ?? null;

  // Payout month = earnings month + 1 (used for half-tax and payout tax calculations)
  const payoutMonth = targetMonth + 1 > 12 ? 1 : targetMonth + 1;
  const lastPayoutMonth = lastMonth + 1 > 12 ? 1 : lastMonth + 1;

  const now = new Date();
  const currentTotals = summarizeShiftTotals({
    shifts: currentMonthShifts,
    halfTaxMonth,
    now,
    month: payoutMonth,
    payoutTaxOverride: payoutTaxSettings ?? undefined,
  });
  const lastMonthTotals = summarizeShiftTotals({
    shifts: lastMonthShifts,
    halfTaxMonth,
    now,
    month: lastPayoutMonth,
    // Note: We don't have payout tax settings for last month from SSR,
    // so we fall back to per-shift tax settings for last month comparison
  });

  // Check if payout tax is enabled (prefer payout settings, fall back to per-shift check)
  const anyTaxEnabled = payoutTaxSettings?.enabled ?? (currentMonthShifts.some(s => s.tax_enabled) || lastMonthShifts.some(s => s.tax_enabled));
  const projectedCurrent = anyTaxEnabled ? currentTotals.net : currentTotals.gross;
  const projectedLastMonth = anyTaxEnabled ? lastMonthTotals.net : lastMonthTotals.gross;

  let percentageChange: number | undefined;
  if (projectedLastMonth > 0) {
    percentageChange = Math.round(
      ((projectedCurrent - projectedLastMonth) / projectedLastMonth) * 100
    );
  }

  // Earned to date (respects tax setting) - this is the primary big number
  const earnedToDate = anyTaxEnabled ? currentTotals.completedNet : currentTotals.completedGross;

  return {
    total: formatCurrency(earnedToDate),
    percentageChange,
    projectedTotal: formatCurrency(projectedCurrent),
    // Gross before tax (only relevant when tax is enabled)
    grossBeforeTax: anyTaxEnabled ? formatCurrency(currentTotals.completedGross) : undefined,
    projectedGrossBeforeTax: anyTaxEnabled ? formatCurrency(currentTotals.gross) : undefined,
  };
}

function isCurrentMonth(date: Date): boolean {
  const now = new Date();
  return (
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth()
  );
}

function isFutureMonth(date: Date): boolean {
  const now = new Date();
  return (
    date.getFullYear() > now.getFullYear() ||
    (date.getFullYear() === now.getFullYear() && date.getMonth() > now.getMonth())
  );
}

export function HomeContent({ shifts: initialShifts, settings, payoutTaxSettings, currentPayoutTaxSettings, cacheKey, preloadedMonths }: HomeContentProps) {
  const { t, locale } = useTranslations();
  const formatCurrency = useFormatCurrency();
  const router = useRouter();
  const { selectedMonth: month, goToPreviousMonth, goToNextMonth, direction, isHydrated } = useMonth();
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [selectedShift, setSelectedShift] = useState<ShiftWithComputations | null>(null);
  const [additionalShifts, setAdditionalShifts] = useState<ShiftWithComputations[]>([]);
  const [deleting, startDeleteTransition] = useTransition();
  const [deletedShiftIds, setDeletedShiftIds] = useState<Set<string>>(new Set());
  const [shiftOverrides, setShiftOverrides] = useState<Map<string, ShiftWithComputations>>(new Map());
  const selectedMonthIsCurrent = isCurrentMonth(month);
  const selectedMonthIsFuture = isFutureMonth(month);

  // Track which months have been loaded or are currently loading
  // Using refs to avoid recreating fetchMonth callback on every state change
  const loadedMonthsRef = useRef<Set<string>>(new Set());
  const loadingMonthsRef = useRef<Set<string>>(new Set());
  const hasInitializedRef = useRef(false);
  // Track the previous initialShifts reference to detect actual SSR data changes
  // vs cacheComponents reveals (where the reference stays the same)
  const prevInitialShiftsRef = useRef<ShiftWithComputations[]>(initialShifts);
  // Track if the currently selected month is loading (for UI feedback)
  // We use both a synchronous check (for initial render) and state (for async updates)
  const [isLoadingAsync, setIsLoadingAsync] = useState(false);
  // Track payout tax settings per month (key: "YYYY-MM" of EARNINGS month)
  // API fetches store settings keyed by the requested (earnings) month
  const [payoutTaxByMonth, setPayoutTaxByMonth] = useState<Map<string, PayoutTaxSettings>>(
    () => new Map()
  );

  // Initialize loaded months synchronously on first render
  // This must happen before any effects run
  // Use a separate flag to prevent re-initialization in React Strict Mode
  if (!hasInitializedRef.current) {
    hasInitializedRef.current = true;
    // Mark all preloaded months as loaded (SSR now loads 3 months: prev, current, next)
    if (preloadedMonths && preloadedMonths.length > 0) {
      preloadedMonths.forEach(key => loadedMonthsRef.current.add(key));
    } else {
      // Fallback: only mark current month if preloadedMonths not provided
      const now = new Date();
      const currentKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      loadedMonthsRef.current.add(currentKey);
    }
  }

  // Combine initial shifts with any dynamically loaded shifts, letting newer data override older entries
  const shifts = useMemo(() => {
    const byId = new Map<string, ShiftWithComputations>();

    initialShifts.forEach(shift => {
      if (!deletedShiftIds.has(shift.id)) {
        byId.set(shift.id, shift);
      }
    });

    additionalShifts.forEach(shift => {
      if (!deletedShiftIds.has(shift.id)) {
        byId.set(shift.id, shift);
      }
    });

    return Array.from(byId.values()).map(shift => {
      const override = shiftOverrides.get(shift.id);
      return override ? { ...shift, ...override } : shift;
    });
  }, [initialShifts, additionalShifts, deletedShiftIds, shiftOverrides]);

  // Reset optimistic updates when new data arrives from server (after router.refresh())
  // Skip if same reference (cacheComponents reveal, not actual data change)
  useEffect(() => {
    if (prevInitialShiftsRef.current === initialShifts) {
      return;
    }
    prevInitialShiftsRef.current = initialShifts;

    // Clear optimistic updates since we have fresh SSR data
    setDeletedShiftIds(new Set());
    setShiftOverrides(new Map());

    // Re-initialize loaded months from the new SSR data
    // This handles the case where the server returns different preloaded months
    loadedMonthsRef.current.clear();
    if (preloadedMonths && preloadedMonths.length > 0) {
      preloadedMonths.forEach(key => loadedMonthsRef.current.add(key));
    } else {
      const now = new Date();
      const currentKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      loadedMonthsRef.current.add(currentKey);
    }

    // Clear additional shifts since SSR data is fresh
    setAdditionalShifts([]);
  }, [initialShifts, preloadedMonths]);

  // Helper to generate month key for tracking
  const getMonthKey = useCallback((year: number, month: number): string => {
    return `${year}-${String(month).padStart(2, '0')}`;
  }, []);

  // Compute loading state synchronously - this ensures we know if month needs loading
  // on the first render after month changes (before useEffect runs)
  const currentMonthKey = getMonthKey(month.getFullYear(), month.getMonth() + 1);
  const isCurrentMonthLoading = isLoadingAsync || !loadedMonthsRef.current.has(currentMonthKey);

  // Helper to fetch a month's shifts and update state
  const fetchMonth = useCallback(async (year: number, month: number, options?: { force?: boolean }) => {
    const key = getMonthKey(year, month);
    const force = options?.force ?? false;

    // Skip if already loaded or currently loading, unless forcing a refresh
    if (!force && (loadedMonthsRef.current.has(key) || loadingMonthsRef.current.has(key))) {
      return;
    }

    // Avoid double-loading the same month
    if (loadingMonthsRef.current.has(key)) {
      return;
    }

    // Mark as loading
    loadingMonthsRef.current.add(key);

    try {
      // Include cacheKey to ensure browser HTTP cache is per-user
      const response = await fetch(`/api/shifts?year=${year}&month=${month}&_ck=${cacheKey}`);
      const data = await response.json();

      if (data.shifts && Array.isArray(data.shifts)) {
        setAdditionalShifts(prev => {
          // Merge refreshed data, letting the latest payload override previous additional entries
          const byId = new Map<string, ShiftWithComputations>();
          [...prev, ...data.shifts].forEach((s: ShiftWithComputations) => byId.set(s.id, s));
          return Array.from(byId.values());
        });

        // Store payout tax settings for this month
        if (data.payoutTaxSettings !== undefined) {
          setPayoutTaxByMonth(prev => new Map(prev).set(key, data.payoutTaxSettings));
        }

        // Mark as successfully loaded
        loadedMonthsRef.current.add(key);
      }
    } catch (err) {
      console.error(`Failed to fetch month ${key}:`, err);
    } finally {
      // Remove from loading set
      loadingMonthsRef.current.delete(key);
    }
  }, [getMonthKey, cacheKey]);

  // Proactive prefetch: Load current and adjacent months when navigating outside the preloaded window
  // SSR preloads 3 months (prev, current, next), so this only triggers when user
  // navigates beyond that window. fetchMonth skips already-loaded months.
  useEffect(() => {
    const selectedYear = month.getFullYear();
    const selectedMonthNum = month.getMonth() + 1;
    const currentKey = getMonthKey(selectedYear, selectedMonthNum);

    // Check if current month needs to be loaded
    const needsLoading = !loadedMonthsRef.current.has(currentKey);

    // Show loading state immediately if needed, with minimum 250ms display time
    let loadingStartTime: number | null = null;
    let minLoadingTimeout: ReturnType<typeof setTimeout> | null = null;

    if (needsLoading) {
      setIsLoadingAsync(true);
      loadingStartTime = Date.now();
    }

    // Calculate prev and next months relative to selected month
    const prevDate = new Date(selectedYear, selectedMonthNum - 2, 1);
    const nextDate = new Date(selectedYear, selectedMonthNum, 1);

    const prevYear = prevDate.getFullYear();
    const prevMonthNum = prevDate.getMonth() + 1;
    const nextYear = nextDate.getFullYear();
    const nextMonthNum = nextDate.getMonth() + 1;

    // Fetch current month and adjacent months in parallel (skips if already loaded from SSR or previous fetches)
    // Current month must be fetched too in case user navigated far away in another route
    Promise.all([
      fetchMonth(selectedYear, selectedMonthNum),
      fetchMonth(prevYear, prevMonthNum),
      fetchMonth(nextYear, nextMonthNum),
    ]).finally(() => {
      if (needsLoading && loadingStartTime) {
        // Ensure loading state is shown for at least 250ms to avoid flash
        const elapsed = Date.now() - loadingStartTime;
        const remaining = Math.max(0, 250 - elapsed);

        if (remaining > 0) {
          minLoadingTimeout = setTimeout(() => {
            setIsLoadingAsync(false);
          }, remaining);
        } else {
          setIsLoadingAsync(false);
        }
      }
    });

    return () => {
      if (minLoadingTimeout) {
        clearTimeout(minLoadingTimeout);
      }
    };
  }, [month, fetchMonth, getMonthKey]);

  // Refresh the currently viewed month when the page regains focus to avoid stale totals after edits elsewhere
  useEffect(() => {
    const handleVisibilityOrFocus = () => {
      if (document.visibilityState === "visible") {
        fetchMonth(month.getFullYear(), month.getMonth() + 1, { force: true });
      }
    };

    window.addEventListener("visibilitychange", handleVisibilityOrFocus);
    window.addEventListener("focus", handleVisibilityOrFocus);
    return () => {
      window.removeEventListener("visibilitychange", handleVisibilityOrFocus);
      window.removeEventListener("focus", handleVisibilityOrFocus);
    };
  }, [month, fetchMonth]);

  // Pre-index shifts by year-month for O(1) lookups instead of O(n) filtering
  const shiftsByMonth = useMemo(() => {
    const index = new Map<string, ShiftWithComputations[]>();

    shifts.forEach(shift => {
      const yearMonth = shift.shift_date.substring(0, 7); // "2025-01"
      if (!index.has(yearMonth)) {
        index.set(yearMonth, []);
      }
      index.get(yearMonth)!.push(shift);
    });

    return index;
  }, [shifts]);

  // Get payout tax settings for the currently selected month (for TotalCard)
  // This is the tax rate for selected month's earnings paid NEXT month
  // Falls back to SSR-provided settings if not yet fetched for this month
  const selectedMonthPayoutTaxSettings = useMemo(() => {
    const key = `${month.getFullYear()}-${String(month.getMonth() + 1).padStart(2, '0')}`;
    return payoutTaxByMonth.get(key) ?? payoutTaxSettings ?? null;
  }, [month, payoutTaxByMonth, payoutTaxSettings]);

  const data = useMemo(
    () => calculateMonthData(shiftsByMonth, month, settings, formatCurrency, selectedMonthPayoutTaxSettings),
    [shiftsByMonth, month, settings, formatCurrency, selectedMonthPayoutTaxSettings]
  );

  // Check if any shifts have tax enabled (for UI display purposes)
  // Prefer payout tax settings if available, otherwise fall back to per-shift check
  const taxDeductionEnabled = useMemo(() => {
    return selectedMonthPayoutTaxSettings?.enabled ?? shifts.some(shift => shift.tax_enabled);
  }, [shifts, selectedMonthPayoutTaxSettings]);

  // Check if user has shifts this month but none have completed yet
  // Also count how many future/planned shifts there are and total shifts
  const { hasPendingShifts, plannedShiftsCount, totalShiftsCount } = useMemo(() => {
    const targetYear = month.getFullYear();
    const targetMonth = month.getMonth() + 1;
    const targetKey = `${targetYear}-${String(targetMonth).padStart(2, '0')}`;
    const monthShifts = shiftsByMonth.get(targetKey) || [];

    if (monthShifts.length === 0) return { hasPendingShifts: false, plannedShiftsCount: 0, totalShiftsCount: 0 };

    const now = new Date();
    const completedShifts = monthShifts.filter(shift => hasShiftEnded(shift, now));
    const futureShifts = monthShifts.filter(shift => !hasShiftEnded(shift, now));

    // Has pending shifts if there are shifts but none have completed
    return {
      hasPendingShifts: completedShifts.length === 0,
      plannedShiftsCount: futureShifts.length,
      totalShiftsCount: monthShifts.length,
    };
  }, [shiftsByMonth, month]);

  const totalCardTotal = selectedMonthIsFuture ? data.projectedTotal : data.total;
  // Only show dashes placeholder for future months without tax AND no planned shifts
  // (when there are planned shifts, TotalCard will show "X vakter planlagt" instead)
  const totalCardSubtitle = selectedMonthIsFuture && !taxDeductionEnabled && plannedShiftsCount === 0 ? "— — —" : undefined;
  const totalCardProjectedTotal = selectedMonthIsFuture ? undefined : data.projectedTotal;
  const totalCardGrossBeforeTax = selectedMonthIsFuture
    ? data.projectedGrossBeforeTax
    : data.grossBeforeTax;

  const payrollDay = Number(settings.payroll_day) || 1;

  // Calculate payroll data and date based on selected month
  const payrollData = useMemo(() => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    let payrollMonthDate: Date;
    let earningsMonthDate: Date;
    let showPreviousPayroll = false;

    if (selectedMonthIsCurrent) {
      // For current month we keep showing this month's payroll even after payday
      payrollMonthDate = new Date(today.getFullYear(), today.getMonth(), 1);
      earningsMonthDate = new Date(
        today.getFullYear(),
        today.getMonth() - 1,
        1
      );
      // Calculate the adjusted payroll date and compare
      const adjustedPayrollDate = adjustPayrollDate(
        payrollDay,
        today.getMonth(),
        today.getFullYear(),
        locale
      );
      showPreviousPayroll = today > adjustedPayrollDate;
    } else {
      // For non-current months: show the selected month's payroll paying for previous month
      payrollMonthDate = new Date(month.getFullYear(), month.getMonth(), 1);
      earningsMonthDate = new Date(
        month.getFullYear(),
        month.getMonth() - 1,
        1
      );
    }

    // O(1) lookup for earnings month
    const targetYear = earningsMonthDate.getFullYear();
    const targetMonth = earningsMonthDate.getMonth() + 1;
    const earningsKey = `${targetYear}-${String(targetMonth).padStart(2, '0')}`;
    const relevantShifts = shiftsByMonth.get(earningsKey) || [];

    const basePay = relevantShifts.reduce(
      (sum, shift) => sum + (shift.computed.basePay || 0),
      0
    );

    // Tax settings are now per-shift, but half_tax_month is still global
    const globalHalfTaxMonth = settings.half_tax_month ?? null;

    // Use payout month (payrollMonthDate) for half tax check, not earnings month
    const payoutMonth = payrollMonthDate.getMonth() + 1;

    // Get payout tax settings for NextPayrollCard:
    // - For current month: use currentPayoutTaxSettings (SSR prop for current payout)
    // - For other months: look up from Map (populated by API fetches, keyed by earnings month)
    const effectivePayoutTaxSettings = selectedMonthIsCurrent
      ? currentPayoutTaxSettings
      : payoutTaxByMonth.get(earningsKey) ?? null;

    const totals = summarizeShiftTotals({
      shifts: relevantShifts,
      halfTaxMonth: globalHalfTaxMonth,
      month: payoutMonth,
      payoutTaxOverride: effectivePayoutTaxSettings ?? undefined,
    });

    const taxAmount = totals.gross - totals.net;
    const netAmount = totals.net;

    // Check if the earnings month is loaded (for loading state)
    const isEarningsMonthLoaded = loadedMonthsRef.current.has(earningsKey);

    return {
      netAmount,
      grossAmount: totals.gross,
      baseAmount: basePay,
      supplementAmount: totals.supplement,
      taxAmount,
      payrollMonthDate,
      hasPayout: relevantShifts.length > 0,
      showPreviousPayroll,
      isEarningsMonthLoaded,
    };
  }, [month, settings, shiftsByMonth, payrollDay, selectedMonthIsCurrent, locale, currentPayoutTaxSettings, payoutTaxByMonth]);

  // Find shift to display based on selected month
  const displayShift = useMemo(() => {
    if (shifts.length === 0) return null;

    if (selectedMonthIsCurrent) {
      // For current month: show active shift, next upcoming shift, or last shift
      const now = new Date();

      // Sort shifts by date and time
      const sortedShifts = [...shifts].sort((a, b) => {
        const dateCompare = a.shift_date.localeCompare(b.shift_date);
        if (dateCompare !== 0) return dateCompare;
        return a.start_time.localeCompare(b.start_time);
      });

      // Helper to parse shift times, handling cross-midnight
      const parseShiftTimes = (shift: typeof sortedShifts[0]) => {
        const [startH, startM] = shift.start_time.split(':').map(Number);
        const [endH, endM] = shift.end_time.split(':').map(Number);

        const start = new Date(shift.shift_date + 'T00:00:00');
        start.setHours(startH, startM, 0, 0);

        const end = new Date(shift.shift_date + 'T00:00:00');
        end.setHours(endH, endM, 0, 0);

        // Handle cross-midnight: if end <= start, end is next day
        if (end <= start) {
          end.setDate(end.getDate() + 1);
        }

        return { start, end };
      };

      // First, check if there's a currently active shift
      for (const shift of sortedShifts) {
        const { start, end } = parseShiftTimes(shift);
        if (now >= start && now <= end) {
          return shift;
        }
      }

      // No active shift, find next upcoming shift
      for (const shift of sortedShifts) {
        const [hours, minutes] = shift.start_time.split(':').map(Number);
        const shiftDateTime = new Date(shift.shift_date + 'T00:00:00');
        shiftDateTime.setHours(hours, minutes, 0, 0);

        if (shiftDateTime > now) {
          return shift;
        }
      }

      // No future shifts, return the last shift
      return sortedShifts[sortedShifts.length - 1];
    } else {
      // For other months: show shift with highest earnings in selected month
      const targetYear = month.getFullYear();
      const targetMonth = month.getMonth() + 1;
      const targetKey = `${targetYear}-${String(targetMonth).padStart(2, '0')}`;

      // O(1) lookup instead of O(n) filtering
      const monthShifts = shiftsByMonth.get(targetKey) || [];

      if (monthShifts.length === 0) return null;

      // Find maximum gross earnings
      const maxGross = Math.max(...monthShifts.map(s => s.computed.gross || 0));

      // Get all shifts with max earnings, then sort chronologically
      const topShifts = monthShifts
        .filter(s => s.computed.gross === maxGross)
        .sort((a, b) => {
          const dateCompare = a.shift_date.localeCompare(b.shift_date);
          if (dateCompare !== 0) return dateCompare;
          return a.start_time.localeCompare(b.start_time);
        });

      // Return the first one chronologically
      return topShifts[0];
    }
  }, [shifts, shiftsByMonth, month, selectedMonthIsCurrent]);

  // Live countdown to next shift - updates every second when close or active
  const countdown = useCountdown({
    shiftDate: selectedMonthIsCurrent && displayShift ? displayShift.shift_date : null,
    shiftTime: selectedMonthIsCurrent && displayShift ? displayShift.start_time : null,
    endTime: selectedMonthIsCurrent && displayShift ? displayShift.end_time : null,
    t,
    highPrecision: true,
  });

  // Live countdown to next payroll
  const payrollCountdown = usePayrollCountdown({
    payrollDay,
    selectedMonth: payrollData.payrollMonthDate,
    locale,
    t,
  });

  // For non-current months, show "Best shift" instead of countdown
  const relativeTimeText = selectedMonthIsCurrent
    ? countdown.text
    : displayShift
      ? (t.common.bestShift ?? "Beste vakt")
      : null;

  // Swipe gesture handling for month navigation
  const swipeContainerRef = useSwipe<HTMLDivElement>({
    onSwipeLeft: goToNextMonth,
    onSwipeRight: goToPreviousMonth,
    threshold: 50,
  });

  return (
    <CenteredPageWrapper routeKey="home">
      <div ref={swipeContainerRef} className="flex items-center">
        <div className="flex flex-col gap-6 w-full">
          {payrollDay && (
            <div className="flex flex-col gap-2">
              <p className="text-sm text-text-secondary text-center">{payrollCountdown.text}</p>
              <NextPayrollCard
                payrollDay={payrollDay}
                netAmount={payrollData.netAmount}
                grossAmount={payrollData.grossAmount}
                baseAmount={payrollData.baseAmount}
                supplementAmount={payrollData.supplementAmount}
                taxAmount={payrollData.taxAmount}
                taxEnabled={taxDeductionEnabled}
                selectedMonth={payrollData.payrollMonthDate}
                hasPayout={payrollData.hasPayout}
                showPreviousPayroll={payrollData.showPreviousPayroll}
                progress={payrollCountdown.isPast ? undefined : payrollCountdown.progress}
                isPayrollToday={payrollCountdown.isToday}
                isLoading={!payrollData.isEarningsMonthLoaded}
              />
            </div>
          )}
          <div>
            <TotalCard
              total={totalCardTotal}
              percentageChange={data.percentageChange}
              projectedTotal={totalCardProjectedTotal}
              grossBeforeTax={totalCardGrossBeforeTax}
              animationDirection={direction}
              subtitlePlaceholder={totalCardSubtitle}
              useZeroPlaceholder={!selectedMonthIsFuture}
              hasPendingShifts={hasPendingShifts}
              plannedShiftsCount={plannedShiftsCount}
              totalShiftsCount={totalShiftsCount}
              isLoading={isCurrentMonthLoading}
            />
          </div>
          <div className="flex items-center justify-between -mt-3 -mb-3">
            <MonthPicker
              key={`month-picker-${month.getFullYear()}-${month.getMonth()}`}
              month={month}
              onPreviousMonth={goToPreviousMonth}
              onNextMonth={goToNextMonth}
              direction={direction === 'next' ? 'forward' : direction === 'previous' ? 'backward' : undefined}
              isHydrated={isHydrated}
            />
            <span className="font-medium text-text-muted mr-3">{month.getFullYear()}</span>
          </div>
          <div className="flex flex-col gap-2">
            {displayShift ? (
              <ShiftCard
                shift={displayShift}
                onClick={() => {
                  setSelectedShift(displayShift);
                  setDetailsOpen(true);
                }}
                progress={countdown.isActive ? countdown.progress : undefined}
                taxSettings={{
                  enabled: displayShift?.tax_enabled ?? false,
                  percentage: displayShift?.tax_percentage ?? 0,
                  halfTaxMonth: settings.half_tax_month ?? null,
                }}
              />
            ) : (
              <ShiftCardSkeleton />
            )}
            <p className="text-sm text-text-secondary text-center">{relativeTimeText ?? "---"}</p>
          </div>
        </div>
      </div>
      <ShiftDetails
        isOpen={detailsOpen}
        shift={selectedShift}
        onClose={() => {
          setDetailsOpen(false);
          setSelectedShift(null);
        }}
        onShiftUpdate={(updatedSupplements) => {
          if (!selectedShift) return;

          const baseRate = selectedShift.hourly_wage_snapshot
            ?? selectedShift.computed?.wagePeriods?.[0]?.baseRate
            ?? undefined;
          const rulesForCompute = selectedShift.supplement_rules_snapshot?.rules ?? PRESET_SUPPLEMENT_RULES;

          const shiftForCompute = {
            ...selectedShift,
            custom_supplements: updatedSupplements,
            ...(typeof baseRate === "number" ? { hourly_wage_snapshot: baseRate } : {}),
          };

          let updatedShift: ShiftWithComputations = shiftForCompute;
          try {
            const recomputed = computeShift(shiftForCompute, settings, rulesForCompute);
            updatedShift = { ...shiftForCompute, computed: recomputed };
          } catch (err) {
            console.error("Failed to recompute shift with custom supplements (HomeContent)", err);
          }

          setSelectedShift(updatedShift);
          setShiftOverrides(prev => {
            const next = new Map(prev);
            next.set(updatedShift.id, updatedShift);
            return next;
          });
        }}
        readOnly={true}
        isDeleting={deleting}
        onDelete={(id) => {
          // Optimistically remove the shift from UI immediately
          const shiftId = typeof id === 'string' ? id : id.shiftId;
          setDeletedShiftIds(prev => new Set(prev).add(shiftId));
          setDetailsOpen(false);
          setSelectedShift(null);

          startDeleteTransition(async () => {
            try {
              await deleteShift(id);
              router.refresh();
            } catch (error) {
              // Revert optimistic update on error
              setDeletedShiftIds(prev => {
                const next = new Set(prev);
                next.delete(shiftId);
                return next;
              });
              console.error("Failed to delete shift", error);
            }
          });
        }}
        cacheKey={cacheKey}
      />
    </CenteredPageWrapper>
  );
}
