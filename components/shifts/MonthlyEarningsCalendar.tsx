"use client";

import { useMemo, useState, useEffect, type Ref } from "react";
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

function getTotalEarnings(earningsByDate: EarningsByDate): number {
  return Object.values(earningsByDate).reduce((sum, val) => sum + val, 0);
}

function formatYear(date: Date): string {
  return date.getFullYear().toString();
}

function formatCurrency(value: number): string {
  return new Intl.NumberFormat("nb-NO", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value);
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
  const [prevMonth, setPrevMonth] = useState(month);

  // Track month changes and determine direction locally
  useEffect(() => {
    if (month.getTime() !== prevMonth.getTime()) {
      const isForward = month > prevMonth;
      // Note: These setState calls are intentional to trigger animation state changes when month prop changes
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setLocalDirection(isForward ? 'next' : 'previous');
      setPrevMonth(month);
    }
  }, [month, prevMonth]);

  // Filter shifts once per month change
  const monthlyShifts = useMemo(() => {
    const targetMonth = month.getMonth();
    const targetYear = month.getFullYear();

    return shifts.filter((shift) => {
      const shiftDate = new Date(`${shift.shift_date}T00:00:00`);
      return (
        shiftDate.getMonth() === targetMonth &&
        shiftDate.getFullYear() === targetYear
      );
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

  const totalEarnings = useMemo(
    () => getTotalEarnings(earningsByDate),
    [earningsByDate]
  );

  return (
    <Card ref={containerRef} className="rounded-card border-0">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3 px-0">
        <div className="flex items-center gap-1">
          <MonthPicker
            month={month}
            onPreviousMonth={goToPreviousMonth}
            onNextMonth={goToNextMonth}
          />
          <span className="font-medium text-text-muted ml-1">{formatYear(month)}</span>
        </div>
        <div
          key={`total-${month.getFullYear()}-${month.getMonth()}`}
          className={`font-semibold text-text-primary ${getAnimationClasses(localDirection)}`}
        >
          {formatCurrency(totalEarnings)} kr
        </div>
      </CardHeader>
      <div className="pb-6">
        <ShiftsCalendar
          month={month}
          mode={viewMode}
          earningsByDate={earningsByDate}
          hoursByDate={hoursByDate}
          onMonthChange={onMonthChange}
          onDayClick={onDayClick}
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
