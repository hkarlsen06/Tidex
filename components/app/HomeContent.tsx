"use client";

import { useState, useMemo, useEffect, useCallback, useRef } from "react";
import { TotalCard } from "@/components/app/TotalCard";
import { NextPayrollCard } from "@/components/app/NextPayrollCard";
import { MonthPicker } from "./MonthPicker";
import { ShiftCard } from "@/components/app/ShiftCard";
import ShiftDetails from "@/components/shifts/ShiftDetails";
import { ShiftWithComputations, UserSettings } from "@/lib/payroll";
import { getRelativeTime } from "@/lib/utils/relativeTime";
import { useMonth } from "./MonthContext";
import { useTranslations } from "@/lib/i18n/client";
import { summarizeShiftTotals } from "@/lib/shifts/monthlyTotals";
import { formatCurrency } from "@/lib/formatters";

type HomeContentProps = {
  shifts: ShiftWithComputations[];
  settings: UserSettings;
};

function calculateMonthData(
  shiftsByMonth: Map<string, ShiftWithComputations[]>,
  month: Date,
  settings: UserSettings
): {
  total: string;
  percentageChange?: number;
  tillegg: string;
  grossBeforeTax?: string;
  lastMonthNet?: number;
  earnedToDate: string;
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

  const taxSettings = {
    enabled: settings.tax_deduction_enabled ?? false,
    percentage: Number(settings.tax_percentage) || 0,
  };

  const now = new Date();
  const currentTotals = summarizeShiftTotals({
    shifts: currentMonthShifts,
    taxSettings,
    now,
  });
  const lastMonthTotals = summarizeShiftTotals({
    shifts: lastMonthShifts,
    taxSettings,
    now,
  });

  const taxEnabled = taxSettings.enabled;
  const displayCurrent = taxEnabled ? currentTotals.net : currentTotals.gross;
  const displayLastMonth = taxEnabled ? lastMonthTotals.net : lastMonthTotals.gross;

  let percentageChange: number | undefined;
  if (displayLastMonth > 0) {
    percentageChange = Math.round(
      ((displayCurrent - displayLastMonth) / displayLastMonth) * 100
    );
  }

  return {
    total: formatCurrency(displayCurrent),
    percentageChange,
    tillegg: formatCurrency(currentTotals.supplement),
    grossBeforeTax: taxEnabled ? formatCurrency(currentTotals.gross) : undefined,
    lastMonthNet: lastMonthTotals.net,
    earnedToDate: formatCurrency(
      taxEnabled ? currentTotals.completedNet : currentTotals.completedGross
    ),
  };
}

function isCurrentMonth(date: Date): boolean {
  const now = new Date();
  return (
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth()
  );
}

export function HomeContent({ shifts: initialShifts, settings }: HomeContentProps) {
  const { t } = useTranslations();
  const { selectedMonth: month, goToPreviousMonth, goToNextMonth, direction } = useMonth();
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [selectedShift, setSelectedShift] = useState<ShiftWithComputations | null>(null);
  const [additionalShifts, setAdditionalShifts] = useState<ShiftWithComputations[]>([]);
  const selectedMonthIsCurrent = isCurrentMonth(month);
  const swipeContainerRef = useRef<HTMLDivElement>(null);
  const touchStartX = useRef<number | null>(null);
  const touchStartY = useRef<number | null>(null);
  const isSwiping = useRef<boolean>(false);

  // Track which months have been loaded or are currently loading
  const [loadedMonths, setLoadedMonths] = useState<Set<string>>(new Set());
  const [loadingMonths, setLoadingMonths] = useState<Set<string>>(new Set());

  // Combine initial shifts with any dynamically loaded shifts
  const shifts = useMemo(
    () => [...initialShifts, ...additionalShifts],
    [initialShifts, additionalShifts]
  );

  // Helper to generate month key for tracking
  const getMonthKey = useCallback((year: number, month: number): string => {
    return `${year}-${String(month).padStart(2, '0')}`;
  }, []);

  // Helper to fetch a month's shifts and update state
  const fetchMonth = useCallback(async (year: number, month: number) => {
    const key = getMonthKey(year, month);

    // Skip if already loaded or currently loading
    if (loadedMonths.has(key) || loadingMonths.has(key)) {
      return;
    }

    // Mark as loading
    setLoadingMonths(prev => new Set(prev).add(key));

    try {
      const response = await fetch(`/api/shifts?year=${year}&month=${month}`);
      const data = await response.json();

      if (data.shifts && Array.isArray(data.shifts)) {
        setAdditionalShifts(prev => {
          // Filter out any duplicates before adding
          const existingIds = new Set([...initialShifts, ...prev].map(s => s.id));
          const newShifts = data.shifts.filter((s: ShiftWithComputations) => !existingIds.has(s.id));
          return [...prev, ...newShifts];
        });

        // Mark as successfully loaded
        setLoadedMonths(prev => new Set(prev).add(key));
      }
    } catch (err) {
      console.error(`Failed to fetch month ${key}:`, err);
    } finally {
      // Remove from loading set
      setLoadingMonths(prev => {
        const next = new Set(prev);
        next.delete(key);
        return next;
      });
    }
  }, [getMonthKey, loadedMonths, loadingMonths, initialShifts]);

  // Initialize loaded months from SSR data on mount
  useEffect(() => {
    const loaded = new Set<string>();
    for (const shift of initialShifts) {
      const [year, month] = shift.shift_date.split('-');
      const key = `${year}-${month}`;
      loaded.add(key);
    }
    setLoadedMonths(loaded);
  }, [initialShifts]);

  // Proactive prefetch: Load adjacent months (prev, current, next) whenever month changes
  useEffect(() => {
    const selectedYear = month.getFullYear();
    const selectedMonthNum = month.getMonth() + 1;

    // Calculate prev and next months
    const prevDate = new Date(selectedYear, selectedMonthNum - 2, 1);
    const nextDate = new Date(selectedYear, selectedMonthNum, 1);

    const prevYear = prevDate.getFullYear();
    const prevMonthNum = prevDate.getMonth() + 1;
    const nextYear = nextDate.getFullYear();
    const nextMonthNum = nextDate.getMonth() + 1;

    // Prefetch all 3 months in parallel (fetchMonth checks if already loaded)
    Promise.all([
      fetchMonth(selectedYear, selectedMonthNum), // Current
      fetchMonth(prevYear, prevMonthNum),         // Previous
      fetchMonth(nextYear, nextMonthNum),         // Next
    ]);
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

  const data = useMemo(
    () => calculateMonthData(shiftsByMonth, month, settings),
    [shiftsByMonth, month, settings]
  );

  const payrollDay = Number(settings.payroll_day) || 1;

  // Calculate payroll data and date based on selected month
  const payrollData = useMemo(() => {
    const today = new Date();

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
      showPreviousPayroll = today.getDate() >= payrollDay;
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

    const taxSettings = {
      enabled: settings.tax_deduction_enabled ?? false,
      percentage: Number(settings.tax_percentage) || 0,
    };

    const totals = summarizeShiftTotals({
      shifts: relevantShifts,
      taxSettings,
    });

    const taxAmount = totals.gross - totals.net;
    const netAmount = totals.net;

    return {
      netAmount,
      grossAmount: totals.gross,
      baseAmount: basePay,
      supplementAmount: totals.supplement,
      taxAmount,
      payrollMonthDate,
      hasPayout: relevantShifts.length > 0,
      showPreviousPayroll,
    };
  }, [month, settings, shiftsByMonth, payrollDay, selectedMonthIsCurrent]);

  // Find shift to display based on selected month
  const displayShift = useMemo(() => {
    if (shifts.length === 0) return null;

    if (selectedMonthIsCurrent) {
      // For current month: show next upcoming shift or last shift
      const now = new Date();

      // Sort shifts by date and time
      const sortedShifts = [...shifts].sort((a, b) => {
        const dateCompare = a.shift_date.localeCompare(b.shift_date);
        if (dateCompare !== 0) return dateCompare;
        return a.start_time.localeCompare(b.start_time);
      });

      // Find next upcoming shift
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

  const relativeTimeText = useMemo(() => {
    if (!displayShift) return null;

    if (selectedMonthIsCurrent) {
      return getRelativeTime(displayShift.shift_date, displayShift.start_time, t);
    } else {
      return "Beste vakt";
    }
  }, [displayShift, selectedMonthIsCurrent, t]);

  const taxDeductionEnabled = settings.tax_deduction_enabled ?? false;

  // Swipe gesture handling
  useEffect(() => {
    const container = swipeContainerRef.current;
    if (!container) return;

    const handleTouchStart = (e: TouchEvent) => {
      touchStartX.current = e.touches[0].clientX;
      touchStartY.current = e.touches[0].clientY;
      isSwiping.current = false;
    };

    const handleTouchMove = (e: TouchEvent) => {
      if (touchStartX.current === null || touchStartY.current === null) return;

      const deltaX = e.touches[0].clientX - touchStartX.current;
      const deltaY = e.touches[0].clientY - touchStartY.current;

      // Determine if this is a horizontal swipe (more horizontal than vertical)
      if (!isSwiping.current && Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 10) {
        isSwiping.current = true;
      }

      // If we're swiping horizontally, prevent default scrolling
      if (isSwiping.current) {
        e.preventDefault();
      }
    };

    const handleTouchEnd = (e: TouchEvent) => {
      if (touchStartX.current === null || !isSwiping.current) {
        touchStartX.current = null;
        touchStartY.current = null;
        isSwiping.current = false;
        return;
      }

      const deltaX = e.changedTouches[0].clientX - touchStartX.current;
      const threshold = 50; // Minimum swipe distance in pixels

      if (Math.abs(deltaX) > threshold) {
        if (deltaX > 0) {
          // Swipe right - go to previous month
          goToPreviousMonth();
        } else {
          // Swipe left - go to next month
          goToNextMonth();
        }
      }

      touchStartX.current = null;
      touchStartY.current = null;
      isSwiping.current = false;
    };

    // Add passive: false to allow preventDefault on touchmove
    container.addEventListener('touchstart', handleTouchStart, { passive: true });
    container.addEventListener('touchmove', handleTouchMove, { passive: false });
    container.addEventListener('touchend', handleTouchEnd, { passive: true });

    return () => {
      container.removeEventListener('touchstart', handleTouchStart);
      container.removeEventListener('touchmove', handleTouchMove);
      container.removeEventListener('touchend', handleTouchEnd);
    };
  }, [goToPreviousMonth, goToNextMonth]);

  return (
    <>
      <div ref={swipeContainerRef} className="flex items-center justify-center h-full">
        <div className="flex flex-col gap-6 w-full max-w-md">
          {payrollDay && (
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
            />
          )}
          <TotalCard
            total={data.total}
            percentageChange={data.percentageChange}
            tillegg={data.tillegg}
            taxDeductionEnabled={taxDeductionEnabled}
            grossBeforeTax={data.grossBeforeTax}
            earnedToDate={selectedMonthIsCurrent ? data.earnedToDate : undefined}
            animationDirection={direction}
          />
          <div className="flex items-center justify-between -mt-3 -mb-3">
            <MonthPicker
              month={month}
              onPreviousMonth={goToPreviousMonth}
              onNextMonth={goToNextMonth}
            />
            <span className="font-medium text-text-muted mr-3">{month.getFullYear()}</span>
          </div>
          {displayShift && (
            <div className="flex flex-col gap-2">
              <ShiftCard
                shift={displayShift}
                onClick={() => {
                  setSelectedShift(displayShift);
                  setDetailsOpen(true);
                }}
              />
              {relativeTimeText && (
                <p className="text-xs text-text-muted text-center">{relativeTimeText}</p>
              )}
            </div>
          )}
        </div>
      </div>
      <ShiftDetails
        isOpen={detailsOpen}
        shift={selectedShift}
        onClose={() => {
          setDetailsOpen(false);
          setSelectedShift(null);
        }}
      />
    </>
  );
}
