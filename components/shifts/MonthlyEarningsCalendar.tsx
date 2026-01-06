"use client";

import { useMemo, useState, useEffect, useRef, type Ref } from "react";
import { Clock, Copy, ArrowRightLeft, Info, Trash2, X, RotateCw } from "lucide-react";
import { motion, AnimatePresence } from "motion/react";
import { AnimateActivity } from "motion-plus/animate-activity";
import { SafeAnimateNumber } from "@/components/app/SafeAnimateNumber";
import { useIsRouteActive } from "@/components/app/RouteVisibilityContext";
import { ShiftsCalendar } from "@/components/app/ShiftsCalendar";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { MonthPicker } from "@/components/app/MonthPicker";
import { useMonth } from "@/components/app/MonthContext";
import type { ShiftWithComputations } from "@/lib/payroll";
import type { ISODate, EarningsByDate, HoursByDate } from "@/components/app/calendar-types";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";
import { getMonthlyTotals } from "@/lib/shifts/monthlyTotals";
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
  /** Callback to delete selected shifts (multi-selection) */
  onDeleteSelected?: () => void;
  /** Callback to delete shifts on the single selected date */
  onDeleteSingleDate?: () => void;
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
  /** Route pattern to check for visibility (e.g., '/shifts', '/sharing'). Defaults to '/shifts'. */
  routePattern?: string;
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

  // Helper to strip seconds and leading zero from time (e.g., "08:30:00" -> "8:30")
  const formatTime = (time: string): string => {
    const hhmm = time.substring(0, 5);
    // Remove leading zero from hour (e.g., "08:30" -> "8:30")
    return hhmm.startsWith("0") ? hhmm.substring(1) : hhmm;
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
      start: formatTime(earliestStart),
      end: formatTime(latestEnd),
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

/** Data snapshot for a calendar month, used to preserve state during exit animations */
type CalendarSnapshot = {
  key: string;
  month: Date;
  earningsByDate: EarningsByDate;
  hoursByDate: HoursByDate;
  overlappingDates: Set<ISODate>;
};

/**
 * Wrapper that freezes the calendar MONTH on mount while allowing shift data to update.
 * Ensures smooth exit animations when swiping months - the exiting calendar shows its
 * original month while the new month slides in.
 *
 * KEY INSIGHT: We only freeze the month, NOT the shift data (earningsByDate, hoursByDate).
 * This allows optimistic shifts to appear immediately while still preserving proper exit
 * animations during month transitions.
 *
 * How it works:
 * - AnimatePresence uses a key based on the month (e.g., "calendar-2025-0")
 * - When the month changes, the old component exits with its frozenMonth
 * - The new component mounts with the new month frozen
 * - Within the same month, shift data updates flow through normally
 *
 * Uses state initialization (lazy initializer) to freeze the month on first render.
 * State is used instead of refs to comply with React 19 compiler rules that prohibit
 * reading refs during render.
 */
function FrozenCalendarSlide({
  snapshot,
  mode,
  onMonthChange,
  onDayClick,
  selectedDate,
  selectedDates,
  newlyAddedDates,
  taxSettings,
  highlightDates,
}: {
  snapshot: CalendarSnapshot;
  mode: "money" | "hours";
  onMonthChange: (month: Date) => void;
  onDayClick?: (iso: ISODate, hasShifts: boolean) => void;
  selectedDate?: ISODate | null;
  selectedDates?: Set<ISODate>;
  newlyAddedDates?: Set<string>;
  taxSettings?: TaxSettings;
  highlightDates?: Set<string> | null;
}) {
  // Freeze the month on mount - this ensures exit animations show the original month
  // The key includes the month, so when AnimatePresence triggers exit, this component
  // will still render with its frozen month value
  const [frozenMonth] = useState(() => snapshot.month);

  // IMPORTANT: We only freeze the month, NOT the shift data (earningsByDate, hoursByDate)
  // This allows optimistic shifts to appear immediately while still preserving the
  // correct month during exit animations.
  //
  // Why this works:
  // - Month changes trigger a new key in AnimatePresence, unmounting this instance
  // - The exiting instance keeps its frozenMonth for proper exit animation
  // - Within the same month, data updates flow through normally for optimistic updates

  return (
    <ShiftsCalendar
      month={frozenMonth}
      mode={mode}
      earningsByDate={snapshot.earningsByDate}
      hoursByDate={snapshot.hoursByDate}
      overlappingDates={snapshot.overlappingDates}
      onMonthChange={onMonthChange}
      onDayClick={onDayClick}
      selectedDate={selectedDate}
      selectedDates={selectedDates}
      weekNumberPosition="top-left"
      newlyAddedDates={newlyAddedDates}
      taxSettings={taxSettings}
      highlightDates={highlightDates}
    />
  );
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

export function MonthlyEarningsCalendar({
  shifts,
  month,
  onMonthChange,
  onDayClick,
  selectedDate = null,
  selectedDates,
  onClearMultiSelection,
  onDeleteSelected,
  onDeleteSingleDate,
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
  routePattern = "/shifts",
  monthContext,
  highlightDates,
}: MonthlyEarningsCalendarProps) {
  const { t } = useTranslations();
  const { symbol: currencySymbol, display: currencyDisplay } = useCurrency();
  // Use external month context if provided (for isolated sharing page state),
  // otherwise fall back to global MonthProvider
  const globalMonthContext = useMonth();
  const { goToPreviousMonth, goToNextMonth, direction, isHydrated } = monthContext ?? globalMonthContext;
  // When showEarnings is false, force hours view (money mode not available)
  const [viewMode, setViewMode] = useState<"money" | "hours">("hours");
  const effectiveViewMode = showEarnings ? viewMode : "hours";
  // Two-click delete confirmation for single date selection
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  // Track previous selectedDate to reset confirmingDelete when selection changes
  const prevSelectedDateRef = useRef(selectedDate);
  if (prevSelectedDateRef.current !== selectedDate) {
    prevSelectedDateRef.current = selectedDate;
    if (confirmingDelete) {
      setConfirmingDelete(false);
    }
  }
  // Refreshing state for spinner animation before page reload
  const [refreshing, setRefreshing] = useState(false);
  // Use direction from context - defaults to 'next' when null (for programmatic changes)
  const animationDirection = direction ?? 'next';
  const swipeContainerRef = useRef<HTMLDivElement>(null);
  const touchStartX = useRef<number | null>(null);
  const touchStartY = useRef<number | null>(null);
  const isSwiping = useRef<boolean>(false);

  // Route visibility - when route is hidden by cacheComponents, we skip AnimatePresence
  // to prevent it from accumulating stale keyed children
  const isRouteActive = useIsRouteActive(routePattern);

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

  // Compute the current month key - when route is active, always use the current month
  // When route is hidden, we render without AnimatePresence anyway, so the key doesn't matter
  const currentMonthKey = `${calendarId}-${month.getFullYear()}-${month.getMonth()}`;

  // Current snapshot for the active month (always up-to-date with latest props)
  const currentSnapshot: CalendarSnapshot = {
    key: currentMonthKey,
    month,
    earningsByDate,
    hoursByDate,
    overlappingDates,
  };

  // Calculate totals - use selected shifts only when in multi-selection mode
  // Note: summarizeShiftTotals/getMonthlyTotals now automatically exclude conflicting shifts
  const { totalEarnings, netEarnings, isShowingSelectedTotal } = useMemo(() => {
    // When dates are selected (multi or single), show total for selected shifts only
    const hasMultiSelection = selectedDates && selectedDates.size > 0;
    const hasSingleSelection = selectedDate && !hasMultiSelection;

    if (hasMultiSelection || hasSingleSelection) {
      // Use full shifts array (not monthlyShifts) so selections from other months
      // still contribute to the total when swiping between months
      const selectedShifts = shifts.filter((shift) => {
        if (hasMultiSelection) {
          return selectedDates.has(shift.shift_date as ISODate);
        }
        return shift.shift_date === selectedDate;
      });

      // Sum precomputed values directly from each shift's snapshot
      // This ensures consistent totals regardless of which month is being viewed
      const gross = selectedShifts.reduce((sum, shift) => sum + (shift.computed.gross || 0), 0);
      const net = selectedShifts.reduce((sum, shift) => {
        return sum + calculateShiftNet(shift, taxSettings?.halfTaxMonth);
      }, 0);

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
  }, [shifts, monthlyShifts, month, taxSettings, selectedDates, selectedDate, payoutTaxSettings]);

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
              <MonthPicker
                key={`month-picker-${month.getFullYear()}-${month.getMonth()}`}
                month={month}
                onPreviousMonth={goToPreviousMonth}
                onNextMonth={goToNextMonth}
                direction={animationDirection === 'next' ? 'forward' : 'backward'}
                isHydrated={isHydrated}
                isAnimationEnabled={isHydrated}
                calendarId={calendarId}
              />
              {isShowingSelectedTotal ? (
                <span className="font-semibold text-text-muted ml-1">
                  ({selectedDates?.size ?? 0})
                </span>
              ) : (
                <span className="font-medium text-text-muted ml-1">{formatYear(month)}</span>
              )}
            </div>
            {showEarnings && (() => {
              // Use payout tax settings for determining if tax should be shown
              // Fall back to taxSettings.enabled if no payout tax settings
              const effectiveTaxEnabled = payoutTaxSettings?.enabled ?? taxSettings?.enabled ?? false;
              const displayValue = effectiveTaxEnabled ? netEarnings : totalEarnings;
              const isPrefix = currencyDisplay === 'prefix';

              return (
                <div className="text-right">
                  <div className="font-semibold text-text-primary">
                    {totalEarnings === 0 ? '—' : (
                      <SafeAnimateNumber
                        layout={false}
                        format={{ maximumFractionDigits: 0 }}
                        locales="nb-NO"
                        prefix={isPrefix ? currencySymbol : undefined}
                        suffix={!isPrefix ? ` ${currencySymbol}` : undefined}
                        transition={{
                          visualDuration: 0.8,
                          type: 'spring',
                          bounce: 0.1,
                        }}
                        routePattern={routePattern}
                      >
                        {displayValue}
                      </SafeAnimateNumber>
                    )}
                  </div>
                  {effectiveTaxEnabled && totalEarnings > 0 && (
                    <div className="text-sm text-text-muted">
                      <SafeAnimateNumber
                        layout={false}
                        format={{ maximumFractionDigits: 0 }}
                        locales="nb-NO"
                        prefix={isPrefix ? currencySymbol : undefined}
                        suffix={!isPrefix ? ` ${currencySymbol}` : undefined}
                        transition={{
                          visualDuration: 0.8,
                          type: 'spring',
                          bounce: 0.1,
                        }}
                        routePattern={routePattern}
                      >
                        {totalEarnings}
                      </SafeAnimateNumber>
                    </div>
                  )}
                </div>
              );
            })()}
          </div>
          <div className="pb-6 overflow-hidden relative">
            {/* Static weekday header - stays in place during month transitions */}
            <WeekdayHeader />
            {/*
            When route is active: use AnimatePresence for smooth month transitions
            When route is hidden (cacheComponents): render calendar directly without AnimatePresence
            This prevents AnimatePresence from accumulating stale keyed children while hidden
          */}
            <div className="relative">
              {isRouteActive ? (
                <AnimatePresence initial={false} mode="popLayout" custom={animationDirection}>
                  <motion.div
                    key={currentMonthKey}
                    custom={animationDirection}
                    variants={{
                      initial: (dir: 'next' | 'previous') => ({
                        x: dir === 'next' ? 'calc(100% + 24px)' : 'calc(-100% - 24px)',
                      }),
                      animate: {
                        x: 0,
                        transition: {
                          type: "tween",
                          duration: 0.3,
                          ease: "easeOut",
                        },
                      },
                      exit: (dir: 'next' | 'previous') => ({
                        x: dir === 'next' ? 'calc(-100% - 24px)' : 'calc(100% + 24px)',
                        opacity: 0,
                        transition: {
                          x: {
                            type: "tween",
                            duration: 0.3,
                            ease: "easeOut",
                          },
                          opacity: {
                            type: "tween",
                            duration: 0.25,
                            ease: "easeIn",
                          },
                        },
                      }),
                    }}
                    initial="initial"
                    animate="animate"
                    exit="exit"
                  >
                    <FrozenCalendarSlide
                      snapshot={currentSnapshot}
                      mode={effectiveViewMode}
                      onMonthChange={onMonthChange}
                      onDayClick={onDayClick}
                      selectedDate={selectedDate}
                      selectedDates={selectedDates}
                      newlyAddedDates={newlyAddedDates}
                      taxSettings={taxSettings}
                      highlightDates={highlightDates}
                    />
                  </motion.div>
                </AnimatePresence>
              ) : (
                // When route is hidden, render without AnimatePresence to avoid stale state
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
              )}
            </div>
          </div>
        </div>
        <div className="flex flex-col items-center gap-2 pb-6">
          <div className="flex items-center gap-1 w-full">
            <div className="inline-flex h-11 flex-1 min-w-0 items-center rounded-xl border border-border-subtle bg-surface-secondary/80 p-1 shadow-app-sm dark:shadow-app-inner overflow-hidden">
              {/* Multi-selection mode: show delete (if allowed) and clear buttons */}
              <AnimateActivity
                mode={selectedDates && selectedDates.size > 0 ? "visible" : "hidden"}
                layoutMode="pop"
              >
                <motion.div
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  transition={{ type: "spring", visualDuration: 0.2, bounce: 0.1 }}
                  className="flex h-9 w-full items-center gap-1 rounded-lg bg-surface-primary"
                >
                  {/* Delete button - only shown when onDeleteSelected is provided (not in readOnly mode) */}
                  {onDeleteSelected && (
                    <Button
                      type="button"
                      variant="ghost"
                      onClick={() => onDeleteSelected()}
                      disabled={deleting || isOffline}
                      loading={deleting}
                      title={isOffline ? "Cannot delete while offline" : undefined}
                      className="flex-1 h-9 gap-2 rounded-lg bg-red-500/10 text-red-600 hover:bg-red-500/20 dark:text-red-400 disabled:opacity-50 disabled:cursor-not-allowed"
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
                    className="flex-1 h-9 gap-2 rounded-lg bg-surface-secondary text-text-secondary hover:bg-surface-secondary/80"
                  >
                    <X strokeWidth={2} className="h-4 w-4" />
                    {(selectedDates?.size ?? 0) >= 2 ? t.common.close : t.pages.shifts.actions.clearSelection}
                  </Button>
                </motion.div>
              </AnimateActivity>

              {/* Single date selected mode: show delete/copy/details/move buttons */}
              <AnimateActivity
                mode={selectedDate && !(selectedDates && selectedDates.size > 0) ? "visible" : "hidden"}
                layoutMode="pop"
              >
                <motion.div
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  transition={{ type: "spring", visualDuration: 0.2, bounce: 0.1 }}
                  className="flex h-9 w-full items-center gap-1 rounded-lg bg-surface-primary"
                >
                  {/* Delete button - two-click confirmation, icon only */}
                  {!readOnly && onDeleteSingleDate && (
                    <Button
                      type="button"
                      variant="ghost"
                      onClick={() => {
                        if (confirmingDelete) {
                          onDeleteSingleDate();
                          setConfirmingDelete(false);
                        } else {
                          setConfirmingDelete(true);
                        }
                      }}
                      disabled={deleting || copyMode || moveMode || isOffline}
                      loading={confirmingDelete && deleting}
                      title={isOffline ? "Cannot delete while offline" : undefined}
                      className={cn(
                        "h-9 shrink-0 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed",
                        confirmingDelete
                          ? "w-auto px-3 gap-2 bg-red-600 text-white hover:bg-red-700"
                          : "w-14 bg-red-500/10 text-red-600 hover:bg-red-500/20 dark:text-red-400"
                      )}
                    >
                      <Trash2 strokeWidth={2} className="h-4 w-4" />
                      {confirmingDelete && (
                        <span className="truncate">{t.pages.shifts.details.confirmDeleteButton}</span>
                      )}
                    </Button>
                  )}
                  {/* Copy button - icon only */}
                  {!readOnly && !confirmingDelete && (
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
                      title={t.pages.shifts.actions.copy}
                      className="h-9 w-14 shrink-0 rounded-lg bg-blue-500/10 text-blue-600 hover:bg-blue-500/20 dark:text-blue-400 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <Copy strokeWidth={2} className="h-4 w-4" />
                    </Button>
                  )}
                  <Button
                    type="button"
                    variant={confirmingDelete ? "ghost" : "default"}
                    onClick={() => {
                      if (confirmingDelete) {
                        setConfirmingDelete(false);
                      } else if (copyMode) {
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
                      deleting ||
                      (copyMode ? !onCancelCopy : moveMode ? !onCancelMoveMode : !confirmingDelete && !onOpenDetails)
                    }
                    className={cn(
                      "flex-1 min-w-0 h-9 rounded-lg",
                      confirmingDelete
                        ? "bg-surface-secondary text-text-secondary hover:bg-surface-secondary/80 gap-2"
                        : !(copyMode || moveMode) && "gap-2"
                    )}
                  >
                    {confirmingDelete ? (
                      <>
                        <X strokeWidth={2} className="h-4 w-4 shrink-0" />
                        <span className="truncate">{t.pages.shifts.actions.cancel}</span>
                      </>
                    ) : copyMode || moveMode ? (
                      <span className="truncate">{t.pages.shifts.actions.cancel}</span>
                    ) : (
                      <>
                        <Info strokeWidth={2} className="h-4 w-4 shrink-0" />
                        <span className="truncate">{t.pages.shifts.actions.details}</span>
                      </>
                    )}
                  </Button>
                  {/* Move button - shows text like details */}
                  {!readOnly && !confirmingDelete && (
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
                        "flex-1 min-w-0 h-9 gap-2 rounded-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed",
                        moveMode
                          ? "bg-amber-500/20 text-amber-700 dark:text-amber-400"
                          : "bg-amber-500/10 text-amber-700 hover:bg-amber-500/20 dark:text-amber-300"
                      )}
                    >
                      <ArrowRightLeft strokeWidth={2} className="h-4 w-4 shrink-0" />
                      <span className="truncate">{t.pages.shifts.actions.move}</span>
                    </Button>
                  )}
                </motion.div>
              </AnimateActivity>

              {/* Default view mode toggle: hours/money with animated indicator */}
              <AnimateActivity
                mode={!selectedDate && !(selectedDates && selectedDates.size > 0) ? "visible" : "hidden"}
                layoutMode="pop"
              >
                <motion.div
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  transition={{ type: "spring", visualDuration: 0.2, bounce: 0.1 }}
                  className="flex h-9 w-full items-center relative"
                >
                  {/* Animated background indicator */}
                  <motion.div
                    className="absolute inset-y-0 rounded-lg bg-white dark:bg-slate-700 shadow-app-md"
                    initial={false}
                    animate={{
                      left: viewMode === "hours" || !showEarnings ? 0 : "50%",
                      width: showEarnings ? "50%" : "100%",
                    }}
                    transition={{ type: "spring", visualDuration: 0.25, bounce: 0.15 }}
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    aria-pressed={viewMode === "hours"}
                    onClick={() => setViewMode("hours")}
                    disableAnimation
                    className={cn(
                      "h-full px-4 text-sm flex-1 whitespace-nowrap transition-colors relative z-10 hover:bg-transparent rounded-lg",
                      viewMode === "hours" || !showEarnings
                        ? "text-black dark:text-white font-semibold"
                        : "text-text-muted hover:text-text-primary"
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
                      disableAnimation
                      className={cn(
                        "h-full px-4 text-sm flex-1 whitespace-nowrap transition-colors relative z-10 hover:bg-transparent rounded-lg",
                        viewMode === "money"
                          ? "text-black dark:text-white font-semibold"
                          : "text-text-muted hover:text-text-primary"
                      )}
                    >
                      ---- {currencySymbol}
                    </Button>
                  )}
                </motion.div>
              </AnimateActivity>
            </div>
          </div>
          {/* Refresh button - below toggle, left aligned */}
          <button
            type="button"
            onClick={() => {
              setRefreshing(true);
              window.location.reload();
            }}
            className={cn(
              "flex items-center gap-1.5 text-xs text-text-muted hover:text-text-primary transition-colors py-1",
              refreshing && "opacity-50"
            )}
            aria-label={t.common.refresh}
          >
            <RotateCw strokeWidth={2} className={cn("h-3.5 w-3.5", refreshing && "animate-spin")} />
            <span>{t.common.refresh}</span>
          </button>
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
