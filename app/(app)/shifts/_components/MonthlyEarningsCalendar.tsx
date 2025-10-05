"use client";

import { useState, useMemo } from "react";
import { ShiftsCalendar } from "@/components/app/ShiftsCalendar";
import { Card, CardHeader, CardTitle } from "@/components/app/Card";
import { ShiftWithComputations } from "@/lib/payroll";
import type { ISODate, EarningsByDate } from "@/components/calendar/calendar.types";

type MonthlyEarningsCalendarProps = {
  shifts: ShiftWithComputations[];
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

function formatMonthYear(date: Date): string {
  return new Intl.DateTimeFormat("nb-NO", {
    month: "long",
    year: "numeric",
  }).format(date);
}

function formatCurrency(value: number): string {
  return new Intl.NumberFormat("nb-NO", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value);
}

export function MonthlyEarningsCalendar({
  shifts,
}: MonthlyEarningsCalendarProps) {
  const [month, setMonth] = useState(new Date());

  const earningsByDate = useMemo(
    () => buildEarningsByDate(shifts, month),
    [shifts, month]
  );

  const totalEarnings = useMemo(
    () => getTotalEarnings(earningsByDate),
    [earningsByDate]
  );

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0">
        <CardTitle className="capitalize">{formatMonthYear(month)}</CardTitle>
        <div className="text-lg font-semibold text-text-primary">
          {formatCurrency(totalEarnings)} kr
        </div>
      </CardHeader>
      <div className="px-6 pb-6">
        <ShiftsCalendar
          month={month}
          mode="money"
          earningsByDate={earningsByDate}
          onMonthChange={setMonth}
        />
      </div>
    </Card>
  );
}
