"use client";

import { useMemo, useState } from "react";
import { IconClock } from "@tabler/icons-react";
import { ShiftsCalendar } from "@/components/app/ShiftsCalendar";
import { Card, CardHeader, CardTitle } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { MonthPicker } from "@/components/app/MonthPicker";
import { ShiftWithComputations } from "@/lib/payroll";
import type { ISODate, EarningsByDate, HoursByDate } from "@/components/calendar/calendar.types";
import { cn } from "@/lib/cn";

type MonthlyEarningsCalendarProps = {
  shifts: ShiftWithComputations[];
  month: Date;
  onMonthChange: (month: Date) => void;
  onDayClick?: (iso: ISODate, hasShifts: boolean) => void;
};

function buildEarningsByDate(
  shifts: ShiftWithComputations[],
  month: Date
): EarningsByDate {
  const result: EarningsByDate = {};
  const targetMonth = month.getMonth();
  const targetYear = month.getFullYear();

  for (const shift of shifts) {
    const shiftDate = new Date(`${shift.shift_date}T00:00:00`);
    if (
      shiftDate.getMonth() === targetMonth &&
      shiftDate.getFullYear() === targetYear
    ) {
      const isoDate = shift.shift_date as ISODate;
      result[isoDate] = (result[isoDate] || 0) + shift.computed.gross;
    }
  }

  return result;
}

function buildHoursByDate(
  shifts: ShiftWithComputations[],
  month: Date
): HoursByDate {
  const result: HoursByDate = {};
  const targetMonth = month.getMonth();
  const targetYear = month.getFullYear();

  // Group shifts by date
  const shiftsByDate = new Map<ISODate, ShiftWithComputations[]>();

  for (const shift of shifts) {
    const shiftDate = new Date(`${shift.shift_date}T00:00:00`);
    if (
      shiftDate.getMonth() === targetMonth &&
      shiftDate.getFullYear() === targetYear
    ) {
      const isoDate = shift.shift_date as ISODate;
      const existing = shiftsByDate.get(isoDate) || [];
      existing.push(shift);
      shiftsByDate.set(isoDate, existing);
    }
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

export function MonthlyEarningsCalendar({
  shifts,
  month,
  onMonthChange,
  onDayClick,
}: MonthlyEarningsCalendarProps) {
  const [viewMode, setViewMode] = useState<"money" | "hours">("money");

  const earningsByDate = useMemo(
    () => buildEarningsByDate(shifts, month),
    [shifts, month]
  );

  const hoursByDate = useMemo(
    () => buildHoursByDate(shifts, month),
    [shifts, month]
  );

  const totalEarnings = useMemo(
    () => getTotalEarnings(earningsByDate),
    [earningsByDate]
  );

  const goToPreviousMonth = () => {
    onMonthChange(new Date(month.getFullYear(), month.getMonth() - 1, 1));
  };

  const goToNextMonth = () => {
    onMonthChange(new Date(month.getFullYear(), month.getMonth() + 1, 1));
  };

  return (
    <Card className="rounded-card border-0">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3 px-0">
        <div className="flex items-center gap-1 flex-1">
          <MonthPicker
            month={month}
            onPreviousMonth={goToPreviousMonth}
            onNextMonth={goToNextMonth}
          />
          <span className="font-medium text-text-muted ml-1">{formatYear(month)}</span>
        </div>
        <div className="font-semibold text-text-primary">
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
          weekNumberPosition="top-left"
        />
      </div>
      <div className="flex justify-center pb-6">
        <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 shadow-app-sm dark:shadow-app-inner w-2/3">
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
            ----kr
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
        </div>
      </div>
    </Card>
  );
}
