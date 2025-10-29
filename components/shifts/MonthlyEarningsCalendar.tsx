"use client";

import { useMemo, useState, useEffect, useRef, useCallback, type Ref, type MutableRefObject } from "react";
import { IconClock, IconCopy, IconArrowsExchange, IconInfoCircle } from "@tabler/icons-react";
import { ShiftsCalendar } from "@/components/app/ShiftsCalendar";
import { Card, CardHeader } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { MonthPicker } from "@/components/app/MonthPicker";
import { useMonth } from "@/components/app/MonthContext";
import { ShiftWithComputations } from "@/lib/payroll";
import type { ISODate, EarningsByDate, HoursByDate } from "@/components/calendar/calendar.types";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";
import { getMonthlyTotals } from "@/lib/shifts/monthlyTotals";
import { formatCurrency } from "@/lib/formatters";

type MonthlyEarningsCalendarProps = {
  shifts: ShiftWithComputations[];
  month: Date;
  onMonthChange: (month: Date) => void;
  onDayClick?: (iso: ISODate, hasShifts: boolean) => void;
  selectedDate?: ISODate | null;
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
};

function buildEarningsByDate(shifts: ShiftWithComputations[]): EarningsByDate {
  const result: EarningsByDate = {};
  for (const shift of shifts) {
    const isoDate = shift.shift_date as ISODate;
    result[isoDate] = (result[isoDate] || 0) + shift.computed.gross;
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

function formatYear(date: Date): string {
  return date.getFullYear().toString();
}

// Helper to get animation classes based on direction
function getAnimationClasses(direction: 'next' | 'previous' | null): string {
  if (!direction) return '';

  if (direction === 'next') {
    // Going forward: swipe in from right with fade
    return 'animate-[swipe-in-right_0.4s_ease-in-out]';
  } else {
    // Going backward: swipe in from left with fade
    return 'animate-[swipe-in-left_0.4s_ease-in-out]';
  }
}

function assignRef<T>(ref: Ref<T> | undefined, value: T) {
  if (!ref) {
    return;
  }

  if (typeof ref === "function") {
    ref(value);
    return;
  }

  (ref as MutableRefObject<T>).current = value;
}

export function MonthlyEarningsCalendar({
  shifts,
  month,
  onMonthChange,
  onDayClick,
  selectedDate = null,
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
}: MonthlyEarningsCalendarProps) {
  const { t } = useTranslations();
  const { goToPreviousMonth, goToNextMonth } = useMonth();
  const [viewMode, setViewMode] = useState<"money" | "hours">("money");
  const [localDirection, setLocalDirection] = useState<'next' | 'previous' | null>(null);
  const internalCardRef = useRef<HTMLDivElement | null>(null);
  const swipeAreaRef = useRef<HTMLDivElement | null>(null);
  const suppressClickRef = useRef(false);
  const swipeResetTimeoutRef = useRef<number | null>(null);
  const [swipeEnabled, setSwipeEnabled] = useState(false);

  const setCombinedCardRef = useCallback(
    (node: HTMLDivElement | null) => {
      internalCardRef.current = node;
      assignRef(containerRef, node);
    },
    [containerRef]
  );

  const handleGoToPreviousMonth = useCallback(() => {
    setLocalDirection('previous');
    goToPreviousMonth();
  }, [goToPreviousMonth]);

  const handleGoToNextMonth = useCallback(() => {
    setLocalDirection('next');
    goToNextMonth();
  }, [goToNextMonth]);

  const handleCalendarMonthChange = useCallback((nextMonth: Date) => {
    const normalizedNext = new Date(nextMonth.getFullYear(), nextMonth.getMonth(), 1);
    const normalizedCurrent = new Date(month.getFullYear(), month.getMonth(), 1);

    if (normalizedNext.getTime() !== normalizedCurrent.getTime()) {
      setLocalDirection(normalizedNext > normalizedCurrent ? 'next' : 'previous');
    }

    onMonthChange(nextMonth);
  }, [month, onMonthChange]);

  const handleCalendarDayClick = useCallback(
    (isoDate: ISODate, hasShifts: boolean) => {
      if (suppressClickRef.current) {
        suppressClickRef.current = false;
        return;
      }

      onDayClick?.(isoDate, hasShifts);
    },
    [onDayClick]
  );

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    const mediaQuery = window.matchMedia("(pointer: coarse)");
    const update = () => setSwipeEnabled(mediaQuery.matches);

    update();

    if (typeof mediaQuery.addEventListener === "function") {
      mediaQuery.addEventListener("change", update);
      return () => mediaQuery.removeEventListener("change", update);
    }

    mediaQuery.addListener(update);
    return () => mediaQuery.removeListener(update);
  }, []);

  useEffect(() => {
    if (!swipeEnabled) {
      return;
    }

    const node = swipeAreaRef.current;
    if (!node) {
      return;
    }

    const SWIPE_DISTANCE_THRESHOLD = 60;
    const SWIPE_VERTICAL_LIMIT = 80;
    const SWIPE_ALLOWED_TIME = 600;
    const HORIZONTAL_ACTIVATION_DISTANCE = 10;

    let pointerId: number | null = null;
    let startX = 0;
    let startY = 0;
    let startTime = 0;
    let isHorizontalGesture = false;

    const reset = () => {
      pointerId = null;
      startX = 0;
      startY = 0;
      startTime = 0;
      isHorizontalGesture = false;
    };

    const handlePointerDown = (event: PointerEvent) => {
      if (event.pointerType !== "touch") {
        return;
      }

      pointerId = event.pointerId;
      startX = event.clientX;
      startY = event.clientY;
      startTime = event.timeStamp;
      isHorizontalGesture = false;
    };

    const handlePointerMove = (event: PointerEvent) => {
      if (pointerId === null || event.pointerId !== pointerId || event.pointerType !== "touch") {
        return;
      }

      const deltaX = event.clientX - startX;
      const deltaY = event.clientY - startY;

      if (!isHorizontalGesture) {
        if (Math.abs(deltaY) > Math.abs(deltaX) && Math.abs(deltaY) > HORIZONTAL_ACTIVATION_DISTANCE) {
          reset();
          return;
        }

        if (Math.abs(deltaX) > HORIZONTAL_ACTIVATION_DISTANCE) {
          isHorizontalGesture = true;
        }
      }
    };

    const triggerSwipe = (direction: "next" | "previous") => {
      suppressClickRef.current = true;

      if (swipeResetTimeoutRef.current !== null) {
        window.clearTimeout(swipeResetTimeoutRef.current);
      }

      swipeResetTimeoutRef.current = window.setTimeout(() => {
        suppressClickRef.current = false;
        swipeResetTimeoutRef.current = null;
      }, 250);

      if (direction === "next") {
        handleGoToNextMonth();
      } else {
        handleGoToPreviousMonth();
      }
    };

    const handlePointerUp = (event: PointerEvent) => {
      if (pointerId === null || event.pointerId !== pointerId || event.pointerType !== "touch") {
        reset();
        return;
      }

      const elapsed = event.timeStamp - startTime;
      const deltaX = event.clientX - startX;
      const deltaY = event.clientY - startY;

      if (
        isHorizontalGesture &&
        elapsed <= SWIPE_ALLOWED_TIME &&
        Math.abs(deltaX) >= SWIPE_DISTANCE_THRESHOLD &&
        Math.abs(deltaY) <= SWIPE_VERTICAL_LIMIT
      ) {
        triggerSwipe(deltaX < 0 ? "next" : "previous");
      }

      reset();
    };

    const handlePointerCancel = () => {
      reset();
    };

    node.addEventListener("pointerdown", handlePointerDown);
    node.addEventListener("pointermove", handlePointerMove);
    node.addEventListener("pointerup", handlePointerUp);
    node.addEventListener("pointercancel", handlePointerCancel);
    node.addEventListener("pointerleave", handlePointerCancel);

    return () => {
      node.removeEventListener("pointerdown", handlePointerDown);
      node.removeEventListener("pointermove", handlePointerMove);
      node.removeEventListener("pointerup", handlePointerUp);
      node.removeEventListener("pointercancel", handlePointerCancel);
      node.removeEventListener("pointerleave", handlePointerCancel);
    };
  }, [handleGoToNextMonth, handleGoToPreviousMonth, swipeEnabled]);

  useEffect(() => {
    return () => {
      if (swipeResetTimeoutRef.current !== null) {
        window.clearTimeout(swipeResetTimeoutRef.current);
      }
    };
  }, []);

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
  const earningsByDate = useMemo(
    () => buildEarningsByDate(monthlyShifts),
    [monthlyShifts]
  );

  const hoursByDate = useMemo(
    () => buildHoursByDate(monthlyShifts),
    [monthlyShifts]
  );

  const totalEarnings = useMemo(() => {
    const { gross } = getMonthlyTotals({
      shifts: monthlyShifts,
      year: month.getFullYear(),
      month: month.getMonth() + 1,
    });

    return gross;
  }, [monthlyShifts, month]);

  return (
    <Card ref={setCombinedCardRef} className="rounded-card border-0">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3 px-0">
        <div className="flex items-center gap-1">
          <MonthPicker
            month={month}
            onPreviousMonth={handleGoToPreviousMonth}
            onNextMonth={handleGoToNextMonth}
          />
          <span className="font-medium text-text-muted ml-1">{formatYear(month)}</span>
        </div>
        <div
          key={`total-${month.getFullYear()}-${month.getMonth()}`}
          className={`font-semibold text-text-primary ${getAnimationClasses(localDirection)}`}
        >
          {formatCurrency(totalEarnings)}
        </div>
      </CardHeader>
      <div className="pb-6" ref={swipeAreaRef}>
        <ShiftsCalendar
          month={month}
          mode={viewMode}
          earningsByDate={earningsByDate}
          hoursByDate={hoursByDate}
          onMonthChange={handleCalendarMonthChange}
          onDayClick={handleCalendarDayClick}
          selectedDate={selectedDate}
          weekNumberPosition="top-left"
        />
      </div>
      <div className="flex flex-col items-center gap-2 pb-6">
        <div className="inline-flex min-h-[44px] w-[90%] items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 px-1 py-1 shadow-app-sm dark:shadow-app-inner">
          {selectedDate ? (
            <div className="flex w-full items-center gap-2 rounded-full bg-surface-primary px-1 py-0.5">
              <Button
                type="button"
                variant="ghost"
                onClick={() => onInitiateCopy?.()}
                disabled={
                  !onInitiateCopy ||
                  copyMode ||
                  copying ||
                  moveMode
                }
                loading={copying}
                className="flex-1 h-9 gap-2 rounded-full bg-blue-500/10 text-blue-600 hover:bg-blue-500/20 dark:text-blue-400"
              >
                <IconCopy stroke={2} className="h-4 w-4" />
                {t.pages.shifts.actions.copy}
              </Button>
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
                    <IconInfoCircle stroke={2} className="h-4 w-4" />
                    {t.pages.shifts.actions.details}
                  </>
                )}
              </Button>
              <Button
                type="button"
                variant="ghost"
                onClick={() => onInitiateMove?.()}
                disabled={
                  !onInitiateMove ||
                  copyMode ||
                  moving ||
                  moveMode
                }
                className={cn(
                  "flex-1 h-9 gap-2 rounded-full px-4 text-sm transition-all",
                  moveMode
                    ? "bg-amber-500/20 text-amber-700 dark:text-amber-400"
                    : "bg-amber-500/10 text-amber-700 hover:bg-amber-500/20 dark:text-amber-300"
                )}
              >
                <IconArrowsExchange stroke={2} className="h-4 w-4" />
                {t.pages.shifts.actions.move}
              </Button>
            </div>
          ) : (
            <div className="flex w-full items-center gap-2 rounded-full px-1 py-0.5">
              <Button
                type="button"
                variant="ghost"
                aria-pressed={viewMode === "money"}
                onClick={() => setViewMode("money")}
                className={cn(
                  "h-9 rounded-full px-4 text-sm flex-1 whitespace-nowrap transition-none",
                  viewMode === "money"
                    ? "bg-white dark:bg-slate-700 text-black dark:text-white shadow-app-md font-semibold"
                    : "text-text-muted hover:text-text-primary hover:bg-surface-secondary/50"
                )}
              >
                ---- kr
              </Button>
              <Button
                type="button"
                variant="ghost"
                aria-pressed={viewMode === "hours"}
                onClick={() => setViewMode("hours")}
                className={cn(
                  "h-9 rounded-full px-4 text-sm flex-1 whitespace-nowrap transition-none",
                  viewMode === "hours"
                    ? "bg-white dark:bg-slate-700 text-black dark:text-white shadow-app-md font-semibold"
                    : "text-text-muted hover:text-text-primary hover:bg-surface-secondary/50"
                )}
              >
                <span>--:--</span>
                <IconClock stroke={2} aria-hidden="true" />
              </Button>
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
  );
}
