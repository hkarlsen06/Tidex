"use client";

import { useMemo, useState, useEffect, useRef, type Ref } from "react";
// AnimatePresence temporarily removed while debugging cacheComponents issue
// import { AnimatePresence, motion } from "framer-motion";
import { Clock, Copy, ArrowRightLeft, Info, Trash2, X } from "lucide-react";
import { ShiftsCalendar } from "@/components/app/ShiftsCalendar";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { MonthPicker } from "@/components/app/MonthPicker";
import { useMonth } from "@/components/app/MonthContext";
import type { ShiftWithComputations } from "@/lib/payroll";
import type { ISODate, EarningsByDate, HoursByDate } from "@/components/app/calendar-types";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";
import { getMonthlyTotals, summarizeShiftTotals } from "@/lib/shifts/monthlyTotals";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";
import { useCurrency } from "@/components/providers/CurrencyProvider";

type TaxSettings = {
  enabled: boolean;
  percentage: number;
  halfTaxMonth?: number | null;
};

/**
 * Payout tax settings from the payout month's snapshot.
 * Used for calculating after-tax monthly totals.
 */
type PayoutTaxSettings = {
  readonly enabled: boolean;
  readonly percentage: number;
} | null;

type MonthlyEarningsCalendarProps = {
  shifts: ShiftWithComputations[];
  month: Date;
  onMonthChange: (month: Date) => void;
  onDayClick?: (iso: ISODate, hasShifts: boolean) => void;
  selectedDate?: ISODate | null;
  /** Set of selected dates for multi-selection mode */
  selectedDates?: Set<ISODate>;
  /** Callback to clear multi-selection */
  onClearMultiSelection?: () => void;
  /** Callback to delete selected shifts */
  onDeleteSelected?: () => void;
  /** Whether deletion is in progress */
  deleting?: boolean;
  containerRef?: Ref<HTMLDivElement>;
  onClearSelection?: () => void;
  onOpenDetails?: () => void;
  copyMode?: boolean;
  onInitiateCopy?: () => void;
  copying?: boolean;
  onCancelCopy?: () => void;
  onInitiateMove?: () => void;
  moveMode?: boolean;
  moving?: boolean;
  onCancelMoveMode?: () => void;
  newlyAddedDates?: Set<string>;
  isOffline?: boolean;
  taxSettings?: TaxSettings;
  /** Payout month tax settings for calculating after-tax monthly totals */
  payoutTaxSettings?: PayoutTaxSettings;
  /** When true, hides copy/move action buttons (for shared shifts view) */
  readOnly?: boolean;
  /** When false, hides earnings-related data (for shared shifts with earnings hidden) */
  showEarnings?: boolean;
  /** Unique identifier for this calendar instance - prevents AnimatePresence key collisions between routes */
  calendarId?: string;
  /** Optional external month context to isolate navigation from global MonthProvider */
  monthContext?: {
    goToPreviousMonth: () => void;
    goToNextMonth: () => void;
    direction: 'next' | 'previous' | null;
    isHydrated: boolean;
  };
  /** Deep link: dates to highlight in calendar (from push notification) */
  highlightDates?: Set<string> | null;
};

/**
 * Calculate net earnings for a single shift, applying per-shift tax settings
 * and half-tax month logic based on payout month.
 */
function calculateShiftNet(
  shift: ShiftWithComputations,
  halfTaxMonth: number | null | undefined
): number {
  const gross = shift.computed.gross || 0;
  const taxEnabled = shift.tax_enabled ?? false;
  let taxPercentage = taxEnabled ? (shift.tax_percentage ?? 0) : 0;

  // Half-tax is applied based on PAYOUT month (shift month + 1), not the shift month itself
  // Example: November shifts are paid in December, so if halfTaxMonth=12, November shifts get half tax
  const shiftMonth = parseInt(shift.shift_date.substring(5, 7), 10);
  const payoutMonth = shiftMonth === 12 ? 1 : shiftMonth + 1;
  if (taxEnabled && halfTaxMonth && payoutMonth === halfTaxMonth) {
    taxPercentage = taxPercentage / 2;
  }

  return taxEnabled ? gross * (1 - taxPercentage / 100) : gross;
}

function buildEarningsByDate(
  shifts: ShiftWithComputations[],
  halfTaxMonth?: number | null
): EarningsByDate {
  const result: EarningsByDate = {};
  for (const shift of shifts) {
    const isoDate = shift.shift_date as ISODate;
    // Use per-shift tax settings from snapshot (single source of truth)
    // This ensures calendar cells match shift card amounts
    const earnings = calculateShiftNet(shift, halfTaxMonth);
    result[isoDate] = (result[isoDate] || 0) + earnings;
  }
  return result;
}

function buildHoursByDate(shifts: ShiftWithComputations[]): HoursByDate {
  const result: HoursByDate = {};
  const shiftsByDate = new Map<ISODate, ShiftWithComputations[]>();

  // Helper to strip seconds from time (e.g., "12:30:00" -> "12:30")
  const stripSeconds = (time: string): string => {
    return time.substring(0, 5);
  };

  for (const shift of shifts) {
    const isoDate = shift.shift_date as ISODate;
    const existing = shiftsByDate.get(isoDate) || [];
    existing.push(shift);
    shiftsByDate.set(isoDate, existing);
  }

  // For each date, show earliest start to latest end
  shiftsByDate.forEach((shiftsOnDate, isoDate) => {
    const sorted = [...shiftsOnDate].sort((a, b) =>
      a.start_time.localeCompare(b.start_time)
    );

    const earliestStart = sorted[0].start_time;
    const latestEnd = sorted.reduce((latest, shift) => {
      return shift.end_time > latest ? shift.end_time : latest;
    }, sorted[0].end_time);

    // Check if ANY shift crosses midnight
    const hasMidnightCrossing = shiftsOnDate.some(shift => {
      const startMinutes = parseInt(shift.start_time.split(':')[0]) * 60 +
                          parseInt(shift.start_time.split(':')[1]);
      const endMinutes = parseInt(shift.end_time.split(':')[0]) * 60 +
                        parseInt(shift.end_time.split(':')[1]);
      return endMinutes <= startMinutes;
    });

    result[isoDate] = {
      start: stripSeconds(earliestStart),
      end: stripSeconds(latestEnd),
      crossesMidnight: hasMidnightCrossing
    };
  });

  return result;
}

/**
 * Detect dates with overlapping shifts.
 * Two shifts overlap if their time ranges intersect.
 * Handles cross-midnight shifts by treating end time as next day.
 */
function buildOverlappingDates(shifts: ShiftWithComputations[]): Set<ISODate> {
  const result = new Set<ISODate>();
  const shiftsByDate = new Map<ISODate, ShiftWithComputations[]>();

  // Group shifts by date
  for (const shift of shifts) {
    const isoDate = shift.shift_date as ISODate;
    const existing = shiftsByDate.get(isoDate) || [];
    existing.push(shift);
    shiftsByDate.set(isoDate, existing);
  }

  // Helper to convert time to minutes since midnight
  const timeToMinutes = (time: string): number => {
    const parts = time.split(':');
    return parseInt(parts[0]) * 60 + parseInt(parts[1]);
  };

  // Check each date for overlapping shifts
  shiftsByDate.forEach((shiftsOnDate, isoDate) => {
    if (shiftsOnDate.length < 2) return; // Need at least 2 shifts to overlap

    // Check all pairs of shifts for overlap
    for (let i = 0; i < shiftsOnDate.length; i++) {
      for (let j = i + 1; j < shiftsOnDate.length; j++) {
        const shiftA = shiftsOnDate[i];
        const shiftB = shiftsOnDate[j];

        let startA = timeToMinutes(shiftA.start_time);
        let endA = timeToMinutes(shiftA.end_time);
        let startB = timeToMinutes(shiftB.start_time);
        let endB = timeToMinutes(shiftB.end_time);

        // Handle cross-midnight shifts: if end <= start, treat end as next day
        if (endA <= startA) endA += 24 * 60;
        if (endB <= startB) endB += 24 * 60;

        // Two ranges [startA, endA] and [startB, endB] overlap if:
        // startA < endB && startB < endA
        if (startA < endB && startB < endA) {
          result.add(isoDate);
          break; // No need to check more pairs for this date
        }
      }
      if (result.has(isoDate)) break;
    }
  });

  return result;
}

function formatYear(date: Date): string {
  return date.getFullYear().toString();
}

/**
 * Static weekday header component - renders outside AnimatePresence
 * to stay fixed during month transitions
 */
function WeekdayHeader() {
  const { locale } = useTranslations();
  const shortNamesEn = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  const shortNamesNb = ['MA', 'TI', 'ON', 'TO', 'FR', 'LØ', 'SØ'];
  const names = locale === 'no' ? shortNamesNb : shortNamesEn;

  return (
    <div className="grid grid-cols-7 mb-2 relative z-10 bg-transparent">
      {names.map((name) => (
        <div key={name} className="text-text-muted font-normal text-xs text-center py-2 uppercase bg-background">
          {name}
        </div>
      ))}
    </div>
  );
}

// Calendar animation variants temporarily removed while debugging cacheComponents issue
// const calendarVariants = { ... }

export function MonthlyEarningsCalendar({
  shifts,
  month,
  onMonthChange,
  onDayClick,
  selectedDate = null,
  selectedDates,
  onClearMultiSelection,
  onDeleteSelected,
  deleting = false,
  containerRef,
  onOpenDetails,
  copyMode = false,
  onInitiateCopy,
  copying = false,
  onCancelCopy,
  onInitiateMove,
  moveMode = false,
  moving = false,
  onCancelMoveMode,
  newlyAddedDates,
  isOffline = false,
  taxSettings,
  payoutTaxSettings,
  readOnly = false,
  showEarnings = true,
  calendarId = "own-shifts",
  monthContext,
  highlightDates,
}: MonthlyEarningsCalendarProps) {
  const { t } = useTranslations();
  const formatCurrency = useFormatCurrency();
  const { symbol: currencySymbol } = useCurrency();
  // Use external month context if provided (for isolated sharing page state),
  // otherwise fall back to global MonthProvider
  const globalMonthContext = useMonth();
  const { goToPreviousMonth, goToNextMonth, direction, isHydrated } = monthContext ?? globalMonthContext;
  // When showEarnings is false, force hours view (money mode not available)
  const [viewMode, setViewMode] = useState<"money" | "hours">("hours");
  const effectiveViewMode = showEarnings ? viewMode : "hours";
  // Use direction from context - defaults to 'next' when null (for programmatic changes)
  const animationDirection = direction ?? 'next';
  const swipeContainerRef = useRef<HTMLDivElement>(null);
  const touchStartX = useRef<number | null>(null);
  const touchStartY = useRef<number | null>(null);
  const isSwiping = useRef<boolean>(false);

  // Track the last rendered month key using a ref (not state) to detect changes
  // when component is revealed after being hidden by cacheComponents.
  // Using ref instead of state avoids the stale closure issues with useState.
  const lastRenderedMonthRef = useRef<string | null>(null);
  const currentMonthKey = `${month.getFullYear()}-${month.getMonth()}`;

  // Detect if this is the first render after being hidden with a different month
  // On first render, lastRenderedMonthRef.current is null, so monthChangedWhileHidden is false
  // On subsequent renders while visible, ref matches currentMonthKey
  // When returning from hidden with different month, ref has old value
  const monthChangedWhileHidden = lastRenderedMonthRef.current !== null &&
                                   lastRenderedMonthRef.current !== currentMonthKey;

  // Track whether animations should be enabled (skip on initial mount)
  const [animationsEnabled, setAnimationsEnabled] = useState(false);

  // Enable animations after initial mount
  useEffect(() => {
    const timer = setTimeout(() => {
      setAnimationsEnabled(true);
    }, 50);
    return () => clearTimeout(timer);
  }, []);

  // Update the ref after every render to track the current month
  // This runs synchronously during render, so it's always up to date
  useEffect(() => {
    lastRenderedMonthRef.current = currentMonthKey;
  });

  // Only animate if: hydrated AND animations enabled AND month didn't change while hidden
  const shouldAnimate = isHydrated && animationsEnabled && !monthChangedWhileHidden;


  // Filter shifts once per month change
  // Include shifts from previous and next month to show on "outside days"
  const monthlyShifts = useMemo(() => {
    const targetMonth = month.getMonth();
    const targetYear = month.getFullYear();

    // Get first day of current month
    const firstDayOfMonth = new Date(targetYear, targetMonth, 1);
    // Get last day of current month
    const lastDayOfMonth = new Date(targetYear, targetMonth + 1, 0);

    // Calculate how many days from previous month are shown
    // (days before the first Monday/week start)
    const firstWeekday = firstDayOfMonth.getDay();
    const daysFromPrevMonth = firstWeekday === 0 ? 6 : firstWeekday - 1; // Monday is week start

    // Calculate how many days from next month are shown
    // (days after the last day to complete the last week)
    const lastWeekday = lastDayOfMonth.getDay();
    const daysFromNextMonth = lastWeekday === 0 ? 0 : 7 - lastWeekday;

    // Create date range that includes outside days
    const rangeStart = new Date(targetYear, targetMonth, 1 - daysFromPrevMonth);
    const rangeEnd = new Date(targetYear, targetMonth + 1, daysFromNextMonth);

    return shifts.filter((shift) => {
      const shiftDate = new Date(`${shift.shift_date}T00:00:00`);
      return shiftDate >= rangeStart && shiftDate <= rangeEnd;
    });
  }, [shifts, month]);

  // Now build functions only process relevant shifts
  // Use per-shift tax settings from snapshot (single source of truth)
  // Only pass halfTaxMonth from user settings for half-tax calculation
  const earningsByDate = useMemo(
    () => buildEarningsByDate(monthlyShifts, taxSettings?.halfTaxMonth),
    [monthlyShifts, taxSettings?.halfTaxMonth]
  );

  const hoursByDate = useMemo(
    () => buildHoursByDate(monthlyShifts),
    [monthlyShifts]
  );

  // Detect dates with overlapping shifts for visual highlighting
  const overlappingDates = useMemo(
    () => buildOverlappingDates(monthlyShifts),
    [monthlyShifts]
  );

  // Calculate totals - use selected shifts only when in multi-selection mode
  // Note: summarizeShiftTotals/getMonthlyTotals now automatically exclude conflicting shifts
  // Payout month = earnings month + 1 (used for half-tax and payout tax calculations)
  const payoutMonth = (month.getMonth() + 2) > 12 ? 1 : month.getMonth() + 2;

  const { totalEarnings, netEarnings, isShowingSelectedTotal } = useMemo(() => {
    // When dates are selected, show total for selected shifts only
    if (selectedDates && selectedDates.size > 0) {
      const selectedShifts = monthlyShifts.filter(
        (shift) => selectedDates.has(shift.shift_date as ISODate)
      );
      const { gross, net } = summarizeShiftTotals({
        shifts: selectedShifts,
        taxSettings,
        now: new Date(),
        month: payoutMonth,
        halfTaxMonth: taxSettings?.halfTaxMonth,
        payoutTaxOverride: payoutTaxSettings ?? undefined,
      });
      return { totalEarnings: gross, netEarnings: net, isShowingSelectedTotal: true };
    }

    // Default: show monthly totals
    const { gross, net } = getMonthlyTotals({
      shifts: monthlyShifts,
      year: month.getFullYear(),
      month: month.getMonth() + 1,
      taxSettings,
      now: new Date(),
      halfTaxMonth: taxSettings?.halfTaxMonth,
      payoutTaxOverride: payoutTaxSettings ?? undefined,
    });

    return { totalEarnings: gross, netEarnings: net, isShowingSelectedTotal: false };
  }, [monthlyShifts, month, taxSettings, selectedDates, payoutMonth, payoutTaxSettings]);

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
      // Use a higher threshold (30px) to avoid interfering with day cell taps on touch devices
      if (!isSwiping.current && Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 30) {
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
    <div>
      <Card ref={containerRef} className="rounded-card border-0 bg-transparent">
        <div ref={swipeContainerRef}>
        <div className="flex h-13 flex-row items-center justify-between">
          <div className="flex h-10 items-center gap-1">
            {isShowingSelectedTotal ? (
              <span className="font-semibold text-text-primary pl-1">
                {t.pages.shifts.actions.selectedCount.replace('{count}', String(selectedDates?.size ?? 0))}
              </span>
            ) : (
              <>
                <MonthPicker
                  month={month}
                  onPreviousMonth={goToPreviousMonth}
                  onNextMonth={goToNextMonth}
                  direction={animationDirection === 'next' ? 'forward' : 'backward'}
                  isHydrated={isHydrated}
                  isAnimationEnabled={shouldAnimate}
                  calendarId={calendarId}
                />
                <span className="font-medium text-text-muted ml-1">{formatYear(month)}</span>
              </>
            )}
          </div>
          {showEarnings && (() => {
            // Use payout tax settings for determining if tax should be shown
            // Fall back to taxSettings.enabled if no payout tax settings
            const effectiveTaxEnabled = payoutTaxSettings?.enabled ?? taxSettings?.enabled ?? false;

            return (
              <div className="text-right">
                <div className="font-semibold text-text-primary">
                  {totalEarnings === 0 ? '—' : formatCurrency(effectiveTaxEnabled ? netEarnings : totalEarnings)}
                </div>
                {effectiveTaxEnabled && totalEarnings > 0 && (
                  <div className="text-sm text-text-muted">
                    {formatCurrency(totalEarnings)}
                  </div>
                )}
              </div>
            );
          })()}
        </div>
        <div className="pb-6 overflow-hidden relative">
          {/* Static weekday header */}
          <WeekdayHeader />
          {/* Calendar without animation - debugging cacheComponents issue */}
          <div key={currentMonthKey}>
            <ShiftsCalendar
              month={month}
              mode={effectiveViewMode}
              earningsByDate={earningsByDate}
              hoursByDate={hoursByDate}
              overlappingDates={overlappingDates}
              onMonthChange={onMonthChange}
              onDayClick={onDayClick}
              selectedDate={selectedDate}
              selectedDates={selectedDates}
              weekNumberPosition="top-left"
              newlyAddedDates={newlyAddedDates}
              taxSettings={taxSettings}
              highlightDates={highlightDates}
            />
          </div>
        </div>
      </div>
      <div className="flex flex-col items-center gap-2 pb-6">
        <div className="inline-flex h-11 w-[90%] max-w-xs items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 shadow-app-sm dark:shadow-app-inner">
          {/* Multi-selection mode: show delete (if allowed) and clear buttons */}
          {selectedDates && selectedDates.size > 0 ? (
            <div className="flex h-full w-full items-center gap-2 rounded-full bg-surface-primary px-1">
              {/* Delete button - only shown when onDeleteSelected is provided (not in readOnly mode) */}
              {onDeleteSelected && (
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => onDeleteSelected()}
                  disabled={deleting || isOffline}
                  loading={deleting}
                  title={isOffline ? "Cannot delete while offline" : undefined}
                  className="flex-1 h-9 gap-2 rounded-full bg-red-500/10 text-red-600 hover:bg-red-500/20 dark:text-red-400 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Trash2 strokeWidth={2} className="h-4 w-4" />
                  {t.pages.shifts.actions.delete}
                </Button>
              )}
              <Button
                type="button"
                variant="ghost"
                onClick={() => onClearMultiSelection?.()}
                disabled={deleting}
                className="flex-1 h-9 gap-2 rounded-full bg-surface-secondary text-text-secondary hover:bg-surface-secondary/80"
              >
                <X strokeWidth={2} className="h-4 w-4" />
                {t.pages.shifts.actions.clearSelection}
              </Button>
            </div>
          ) : selectedDate ? (
            <div className="flex h-full w-full items-center gap-2 rounded-full bg-surface-primary px-1">
              {/* Copy button - hidden in readOnly mode */}
              {!readOnly && (
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => onInitiateCopy?.()}
                  disabled={
                    !onInitiateCopy ||
                    copyMode ||
                    copying ||
                    moveMode ||
                    isOffline
                  }
                  loading={copying}
                  title={isOffline ? "Cannot copy shifts while offline" : undefined}
                  className="flex-1 h-9 gap-2 rounded-full bg-blue-500/10 text-blue-600 hover:bg-blue-500/20 dark:text-blue-400 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Copy strokeWidth={2} className="h-4 w-4" />
                  {t.pages.shifts.actions.copy}
                </Button>
              )}
              <Button
                type="button"
                variant="default"
                onClick={() => {
                  if (copyMode) {
                    onCancelCopy?.();
                  } else if (moveMode) {
                    onCancelMoveMode?.();
                  } else {
                    onOpenDetails?.();
                  }
                }}
                disabled={
                  copying ||
                  moving ||
                  (copyMode ? !onCancelCopy : moveMode ? !onCancelMoveMode : !onOpenDetails)
                }
                className={cn(
                  "flex-1 h-9 rounded-full",
                  !(copyMode || moveMode) && "gap-2"
                )}
              >
                {copyMode || moveMode ? (
                  t.pages.shifts.actions.cancel
                ) : (
                  <>
                    <Info strokeWidth={2} className="h-4 w-4" />
                    {t.pages.shifts.actions.details}
                  </>
                )}
              </Button>
              {/* Move button - hidden in readOnly mode */}
              {!readOnly && (
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => onInitiateMove?.()}
                  disabled={
                    !onInitiateMove ||
                    copyMode ||
                    moving ||
                    moveMode ||
                    isOffline
                  }
                  title={isOffline ? "Cannot move shifts while offline" : undefined}
                  className={cn(
                    "flex-1 h-9 gap-2 rounded-full px-4 text-sm transition-all disabled:opacity-50 disabled:cursor-not-allowed",
                    moveMode
                      ? "bg-amber-500/20 text-amber-700 dark:text-amber-400"
                      : "bg-amber-500/10 text-amber-700 hover:bg-amber-500/20 dark:text-amber-300"
                  )}
                >
                  <ArrowRightLeft strokeWidth={2} className="h-4 w-4" />
                  {t.pages.shifts.actions.move}
                </Button>
              )}
            </div>
          ) : (
            <div className="flex h-full w-full items-center gap-1">
              <Button
                type="button"
                variant="ghost"
                aria-pressed={viewMode === "hours"}
                onClick={() => setViewMode("hours")}
                className={cn(
                  "h-full rounded-full px-4 text-sm flex-1 whitespace-nowrap transition-none",
                  viewMode === "hours" || !showEarnings
                    ? "bg-white dark:bg-slate-700 text-black dark:text-white shadow-app-md font-semibold"
                    : "text-text-muted hover:text-text-primary hover:bg-surface-secondary/50"
                )}
              >
                <span>--:--</span>
                <Clock strokeWidth={2} aria-hidden="true" />
              </Button>
              {/* Money toggle hidden when earnings are not visible */}
              {showEarnings && (
                <Button
                  type="button"
                  variant="ghost"
                  aria-pressed={viewMode === "money"}
                  onClick={() => setViewMode("money")}
                  className={cn(
                    "h-full rounded-full px-4 text-sm flex-1 whitespace-nowrap transition-none",
                    viewMode === "money"
                      ? "bg-white dark:bg-slate-700 text-black dark:text-white shadow-app-md font-semibold"
                      : "text-text-muted hover:text-text-primary hover:bg-surface-secondary/50"
                  )}
                >
                  ---- {currencySymbol}
                </Button>
              )}
            </div>
          )}
        </div>
        {selectedDate && (copyMode || moveMode) && (
          <div className="text-xs font-medium leading-tight text-text-muted text-center">
            {copyMode
              ? t.pages.shifts.actions.copyInstructions
              : t.pages.shifts.actions.moveInstructions}
          </div>
        )}
      </div>
    </Card>
    </div>
  );
}
