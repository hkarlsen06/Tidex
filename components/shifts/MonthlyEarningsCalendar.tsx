"use client";

import { useMemo, useState, useEffect, type Ref } from "react";
import { IconClock, IconCopy } from "@tabler/icons-react";
import { ShiftsCalendar } from "@/components/app/ShiftsCalendar";
import { Card, CardHeader } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { MonthPicker } from "@/components/app/MonthPicker";
import { useMonth } from "@/components/app/MonthContext";
import { ShiftWithComputations } from "@/lib/payroll";
import type { ISODate, EarningsByDate, HoursByDate } from "@/components/calendar/calendar.types";
import { cn } from "@/lib/cn";

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

  for (const shift of shifts) {
    const isoDate = shift.shift_date as ISODate;
    const existing = shiftsByDate.get(isoDate) || [];
    existing.push(shift);
    shiftsByDate.set(isoDate, existing);
  }

  // For each date, get the first shift (by start time)
  shiftsByDate.forEach((shiftsOnDate, isoDate) => {
    const sorted = [...shiftsOnDate].sort((a, b) =>
      a.start_time.localeCompare(b.start_time)
    );
    const firstShift = sorted[0];

    // Check if shift crosses midnight
    const startMinutes = parseInt(firstShift.start_time.split(':')[0]) * 60 +
                        parseInt(firstShift.start_time.split(':')[1]);
    const endMinutes = parseInt(firstShift.end_time.split(':')[0]) * 60 +
                      parseInt(firstShift.end_time.split(':')[1]);

    result[isoDate] = {
      start: firstShift.start_time,
      end: firstShift.end_time,
      crossesMidnight: endMinutes <= startMinutes
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
  onClearSelection,
  onOpenDetails,
  copyMode = false,
  onInitiateCopy,
  copying = false,
  onCancelCopy,
}: MonthlyEarningsCalendarProps) {
  const { goToPreviousMonth, goToNextMonth } = useMonth();
  const [viewMode, setViewMode] = useState<"money" | "hours">("money");
  const [localDirection, setLocalDirection] = useState<'next' | 'previous' | null>(null);
  const [prevMonth, setPrevMonth] = useState(month);

  // Track month changes and determine direction locally
  useEffect(() => {
    if (month.getTime() !== prevMonth.getTime()) {
      const isForward = month > prevMonth;
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
            <div className="flex w-full items-center justify-between gap-2 rounded-full bg-surface-primary px-0 py-0">
              <Button
                type="button"
                variant="ghost"
                onClick={() => onInitiateCopy?.()}
                disabled={!onInitiateCopy || copyMode || copying}
                loading={copying}
                className="flex-1 rounded-full h-9 gap-2 bg-blue-500/10 text-blue-600 hover:bg-blue-500/20 dark:text-blue-400"
              >
                <IconCopy stroke={2} className="h-4 w-4" />
                Kopier
              </Button>
              <Button
                type="button"
                variant="default"
                onClick={() => {
                  if (copyMode) {
                    onCancelCopy?.();
                  } else {
                    onOpenDetails?.();
                  }
                }}
                disabled={
                  copying ||
                  (copyMode ? !onCancelCopy : !onOpenDetails)
                }
                className="flex-[2] rounded-full h-9"
              >
                {copyMode ? "Avbryt" : "Detaljer"}
              </Button>
              {onClearSelection && (
                <Button
                  type="button"
                  variant="ghost"
                  onClick={onClearSelection}
                  className="h-9 flex-1 rounded-full text-xs text-text-secondary hover:text-text-primary"
                >
                  Fjern valg
                </Button>
              )}
            </div>
          ) : (
            <>
              <Button
                type="button"
                variant="ghost"
                aria-pressed={viewMode === "money"}
                onClick={() => setViewMode("money")}
                className={cn(
                  "h-9 rounded-full px-4 text-sm transition-all flex-1 whitespace-nowrap",
                  viewMode === "money"
                    ? "bg-surface-primary text-text-primary shadow-sm"
                    : "text-text-secondary hover:text-text-primary"
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
                  "h-9 rounded-full px-4 text-sm transition-all flex-1 whitespace-nowrap",
                  viewMode === "hours"
                    ? "bg-surface-primary text-text-primary shadow-sm"
                    : "text-text-secondary hover:text-text-primary"
                )}
              >
                <span>--:--</span>
                <IconClock stroke={2} aria-hidden="true" />
              </Button>
            </>
          )}
        </div>
        <div className={`text-xs font-medium leading-tight text-text-muted text-center ${selectedDate ? 'opacity-100' : 'opacity-0'}`}>
          {copyMode ? "Velg en dato for å kopiere vakten dit" : "Velg en annen dato for å flytte vakten"}
        </div>
      </div>
    </Card>
  );
}
