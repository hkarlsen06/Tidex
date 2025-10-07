"use client";

import { useMemo } from "react";
import { IconChevronLeft, IconChevronRight } from "@tabler/icons-react";
import { ShiftsCalendar } from "@/components/app/ShiftsCalendar";
import { Card, CardHeader, CardTitle } from "@/components/app/Card";
import { ShiftWithComputations } from "@/lib/payroll";
import type { ISODate, EarningsByDate } from "@/components/calendar/calendar.types";

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

function getTotalEarnings(earningsByDate: EarningsByDate): number {
  return Object.values(earningsByDate).reduce((sum, val) => sum + val, 0);
}

function formatMonth(date: Date): string {
  return new Intl.DateTimeFormat("nb-NO", {
    month: "long",
  }).format(date);
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
  const earningsByDate = useMemo(
    () => buildEarningsByDate(shifts, month),
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
      <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3">
        <div className="flex items-center gap-1">
          <button
            onClick={goToPreviousMonth}
            className="h-7 w-7 flex items-center justify-center rounded-md hover:bg-surface-secondary transition-colors text-text-primary"
            aria-label="Previous month"
          >
            <IconChevronLeft size={18} />
          </button>
          <span className="capitalize w-24 text-center font-medium text-text-primary">{formatMonth(month)}</span>
          <button
            onClick={goToNextMonth}
            className="h-7 w-7 flex items-center justify-center rounded-md hover:bg-surface-secondary transition-colors text-text-primary"
            aria-label="Next month"
          >
            <IconChevronRight size={18} />
          </button>
          <span className="font-medium text-text-muted ml-1">{formatYear(month)}</span>
        </div>
        <div className="font-semibold text-text-primary">
          {formatCurrency(totalEarnings)} kr
        </div>
      </CardHeader>
      <div className="pb-6">
        <ShiftsCalendar
          month={month}
          mode="money"
          earningsByDate={earningsByDate}
          onMonthChange={onMonthChange}
          onDayClick={onDayClick}
        />
      </div>
    </Card>
  );
}
