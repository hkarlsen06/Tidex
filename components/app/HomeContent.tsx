"use client";

import { useState, useMemo, useEffect, useCallback, useTransition, useRef } from "react";
import { useRouter } from "next/navigation";
import { TotalCard } from "@/components/app/TotalCard";
import { NextPayrollCard } from "@/components/app/NextPayrollCard";
import { MonthPicker } from "./MonthPicker";
import { ShiftCard } from "@/components/app/ShiftCard";
import ShiftDetails from "@/components/shifts/ShiftDetails";
import { ShiftWithComputations, UserSettings, computeShift, PRESET_SUPPLEMENT_RULES } from "@/lib/payroll";
import { useCountdown } from "@/lib/hooks/useCountdown";
import { useMonth } from "./MonthContext";
import { useTranslations } from "@/lib/i18n/client";
import { summarizeShiftTotals } from "@/lib/shifts/monthlyTotals";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";
import { adjustPayrollDate } from "@/lib/payroll/adjust-payroll-date";
import { useSwipe } from "@/lib/hooks/useSwipe";

type HomeContentProps = {
  shifts: ShiftWithComputations[];
  settings: UserSettings;
};

function calculateMonthData(
  shiftsByMonth: Map<string, ShiftWithComputations[]>,
  month: Date,
  settings: UserSettings,
  formatCurrency: (value: number) => string
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

  const taxSettings = {
    enabled: settings.tax_deduction_enabled ?? false,
    percentage: Number(settings.tax_percentage) || 0,
    halfTaxMonth: settings.half_tax_month ?? null,
  };

  // Calculate payout month for half tax check (income earned in targetMonth is paid out next month)
  const payoutMonth = targetMonth === 12 ? 1 : targetMonth + 1;
  const lastMonthPayoutMonth = lastMonth === 12 ? 1 : lastMonth + 1;

  const now = new Date();
  const currentTotals = summarizeShiftTotals({
    shifts: currentMonthShifts,
    taxSettings,
    now,
    month: payoutMonth,
  });
  const lastMonthTotals = summarizeShiftTotals({
    shifts: lastMonthShifts,
    taxSettings,
    now,
    month: lastMonthPayoutMonth,
  });

  const taxEnabled = taxSettings.enabled;
  const projectedCurrent = taxEnabled ? currentTotals.net : currentTotals.gross;
  const projectedLastMonth = taxEnabled ? lastMonthTotals.net : lastMonthTotals.gross;

  let percentageChange: number | undefined;
  if (projectedLastMonth > 0) {
    percentageChange = Math.round(
      ((projectedCurrent - projectedLastMonth) / projectedLastMonth) * 100
    );
  }

  // Earned to date (respects tax setting) - this is the primary big number
  const earnedToDate = taxEnabled ? currentTotals.completedNet : currentTotals.completedGross;

  return {
    total: formatCurrency(earnedToDate),
    percentageChange,
    projectedTotal: formatCurrency(projectedCurrent),
    // Gross before tax (only relevant when tax is enabled)
    grossBeforeTax: taxEnabled ? formatCurrency(currentTotals.completedGross) : undefined,
    projectedGrossBeforeTax: taxEnabled ? formatCurrency(currentTotals.gross) : undefined,
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

export function HomeContent({ shifts: initialShifts, settings }: HomeContentProps) {
  const { t, locale } = useTranslations();
  const formatCurrency = useFormatCurrency();
  const router = useRouter();
  const { selectedMonth: month, goToPreviousMonth, goToNextMonth, direction } = useMonth();
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

  // Initialize loaded months synchronously on first render
  // This must happen before any effects run
  // Use a separate flag to prevent re-initialization in React Strict Mode
  if (!hasInitializedRef.current) {
    hasInitializedRef.current = true;
    // Only mark current month as loaded (SSR data explicitly loads current month only)
    // Do NOT mark other months even if they have shifts in initialShifts,
    // as those might be incomplete data (e.g., recurring virtual shifts spanning multiple months)
    const now = new Date();
    const currentKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    loadedMonthsRef.current.add(currentKey);
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
  useEffect(() => {
    setDeletedShiftIds(new Set());
    setShiftOverrides(new Map());
  }, [initialShifts]);

  // Helper to generate month key for tracking
  const getMonthKey = useCallback((year: number, month: number): string => {
    return `${year}-${String(month).padStart(2, '0')}`;
  }, []);

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
      const response = await fetch(`/api/shifts?year=${year}&month=${month}`);
      const data = await response.json();

      if (data.shifts && Array.isArray(data.shifts)) {
        setAdditionalShifts(prev => {
          // Merge refreshed data, letting the latest payload override previous additional entries
          const byId = new Map<string, ShiftWithComputations>();
          [...prev, ...data.shifts].forEach((s: ShiftWithComputations) => byId.set(s.id, s));
          return Array.from(byId.values());
        });

        // Mark as successfully loaded
        loadedMonthsRef.current.add(key);
      }
    } catch (err) {
      console.error(`Failed to fetch month ${key}:`, err);
    } finally {
      // Remove from loading set
      loadingMonthsRef.current.delete(key);
    }
  }, [getMonthKey, initialShifts]);

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

  const data = useMemo(
    () => calculateMonthData(shiftsByMonth, month, settings, formatCurrency),
    [shiftsByMonth, month, settings, formatCurrency]
  );

  const taxDeductionEnabled = settings.tax_deduction_enabled ?? false;

  const totalCardTotal = selectedMonthIsFuture ? data.projectedTotal : data.total;
  const totalCardSubtitle = selectedMonthIsFuture && !taxDeductionEnabled ? "---" : undefined;
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

    const taxSettings = {
      enabled: settings.tax_deduction_enabled ?? false,
      percentage: Number(settings.tax_percentage) || 0,
      halfTaxMonth: settings.half_tax_month ?? null,
    };

    // Use payout month (payrollMonthDate) for half tax check, not earnings month
    const payoutMonth = payrollMonthDate.getMonth() + 1;

    const totals = summarizeShiftTotals({
      shifts: relevantShifts,
      taxSettings,
      month: payoutMonth,
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
  }, [month, settings, shiftsByMonth, payrollDay, selectedMonthIsCurrent, locale]);

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
    <>
      <div ref={swipeContainerRef} className="flex items-center">
        <div className="flex flex-col gap-6 w-full">
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
            total={totalCardTotal}
            percentageChange={data.percentageChange}
            projectedTotal={totalCardProjectedTotal}
            grossBeforeTax={totalCardGrossBeforeTax}
            animationDirection={direction}
            subtitlePlaceholder={totalCardSubtitle}
            useZeroPlaceholder={!selectedMonthIsFuture}
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
                progress={countdown.isActive ? countdown.progress : undefined}
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
      />
    </>
  );
}
