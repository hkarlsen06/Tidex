"use client";

import { useState, useMemo } from "react";
import { TotalCard } from "@/components/app/TotalCard";
import { MonthPicker } from "./MonthPicker";
import { ShiftWithComputations } from "@/lib/payroll";
import { Card, CardContent } from "@/components/app/Card";
import Link from "next/link";

type HomeContentProps = {
  shifts: ShiftWithComputations[];
};

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

function formatCurrency(value: number): string {
  return `${numberFormatter.format(Math.round(value))} kr`;
}

function calculateMonthData(
  shifts: ShiftWithComputations[],
  month: Date
): {
  total: string;
  percentageChange?: number;
  tillegg: string;
} {
  const targetYear = month.getFullYear();
  const targetMonth = month.getMonth() + 1;

  // Filter current month shifts
  const currentMonthShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return (
      shiftDate.getFullYear() === targetYear &&
      shiftDate.getMonth() + 1 === targetMonth
    );
  });

  // Filter last month shifts
  const lastMonthDate = new Date(targetYear, targetMonth - 2, 1);
  const lastMonthYear = lastMonthDate.getFullYear();
  const lastMonth = lastMonthDate.getMonth() + 1;

  const lastMonthShifts = shifts.filter((shift) => {
    const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
    return (
      shiftDate.getFullYear() === lastMonthYear &&
      shiftDate.getMonth() + 1 === lastMonth
    );
  });

  // Calculate totals
  const gross = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  const bonusPay = currentMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.bonusPay || 0),
    0
  );

  const lastMonthGross = lastMonthShifts.reduce(
    (sum, shift) => sum + (shift.computed.gross || 0),
    0
  );

  // Calculate percentage change
  let percentageChange: number | undefined;
  if (lastMonthGross > 0) {
    percentageChange = Math.round(
      ((gross - lastMonthGross) / lastMonthGross) * 100
    );
  }

  return {
    total: formatCurrency(gross),
    percentageChange,
    tillegg: formatCurrency(bonusPay),
  };
}

export function HomeContent({ shifts }: HomeContentProps) {
  const [month, setMonth] = useState(new Date());

  const data = useMemo(
    () => calculateMonthData(shifts, month),
    [shifts, month]
  );

  const goToPreviousMonth = () => {
    setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1));
  };

  const goToNextMonth = () => {
    setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1));
  };

  return (
    <div className="flex flex-col gap-6">
      <TotalCard
        total={data.total}
        percentageChange={data.percentageChange}
        tillegg={data.tillegg}
      />
      <div className="flex items-center justify-between px-[calc(var(--radius)*3)]">
        <MonthPicker
          month={month}
          onPreviousMonth={goToPreviousMonth}
          onNextMonth={goToNextMonth}
        />
        <span className="font-medium text-text-muted">{month.getFullYear()}</span>
      </div>
      <Card className="border-border bg-surface-primary card">
        <CardContent className="p-6 text-center">
          <p className="text-lg font-medium text-text-primary">
            Vi er for øyeblikket under vedlikehold
          </p>
          <p className="mt-2 text-sm text-text-muted">
            Du kan fortsatt{" "}
            <Link href="/shifts" className="text-brand-gradientStart hover:underline">
              se dine vakter
            </Link>
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
