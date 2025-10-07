"use client";

import { useMemo, useState, useCallback } from "react";

import ShiftCard from "@/components/app/ShiftCard";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/app/Card";
import { MonthlyEarningsCalendar } from "./MonthlyEarningsCalendar";
import { ShiftWithComputations } from "@/lib/payroll";

export type WeekGroup = {
  id: string;
  label: string;
  totalGross: number;
  shifts: ShiftWithComputations[];
};

const weekFormatter = new Intl.NumberFormat("nb-NO", {
  minimumIntegerDigits: 2,
});

const currencyFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

function getIsoWeek(date: Date) {
  const d = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())
  );
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNumber = Math.ceil(
    ((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7
  );
  return { weekNumber, year: d.getUTCFullYear() };
}

function groupByWeek(shifts: ShiftWithComputations[]): WeekGroup[] {
  const groups: WeekGroup[] = [];
  const map = new Map<string, WeekGroup>();

  for (const shift of shifts) {
    const date = new Date(`${shift.shift_date}T00:00:00Z`);
    const { weekNumber, year } = getIsoWeek(date);
    const id = `${year}-${weekNumber}`;

    let group = map.get(id);
    if (!group) {
      group = {
        id,
        label: `Uke ${weekFormatter.format(weekNumber)}`,
        totalGross: 0,
        shifts: [],
      };
      map.set(id, group);
      groups.push(group);
    }

    group.shifts.push(shift);
    group.totalGross += shift.computed.gross;
  }

  for (const group of groups) {
    group.shifts.sort((a, b) => a.shift_date.localeCompare(b.shift_date));
  }

  return groups;
}

function formatWeekTotal(value: number) {
  return `${currencyFormatter.format(Math.round(value))} kr`;
}

function filterShiftsByMonth(
  shifts: ShiftWithComputations[],
  month: Date
): ShiftWithComputations[] {
  const targetMonth = month.getMonth();
  const targetYear = month.getFullYear();

  return shifts.filter((shift) => {
    const shiftDate = new Date(`${shift.shift_date}T00:00:00`);
    return (
      shiftDate.getMonth() === targetMonth &&
      shiftDate.getFullYear() === targetYear
    );
  });
}

function startOfMonth(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

type ShiftsViewProps = {
  shifts: ShiftWithComputations[];
};

export function ShiftsView({ shifts }: ShiftsViewProps) {
  const [selectedMonth, setSelectedMonth] = useState(() => startOfMonth(new Date()));

  const handleMonthChange = useCallback((month: Date) => {
    setSelectedMonth(startOfMonth(month));
  }, []);

  const filteredShifts = useMemo(
    () => filterShiftsByMonth(shifts, selectedMonth),
    [shifts, selectedMonth]
  );

  const grouped = useMemo(() => {
    const groups = groupByWeek(filteredShifts);
    return [...groups].reverse();
  }, [filteredShifts]);

  const hasAnyShifts = shifts.length > 0;
  const emptyTitle = hasAnyShifts
    ? "Ingen skift for denne måneden"
    : "Ingen skift registrert ennå";
  const emptyDescription = hasAnyShifts
    ? "Prøv å velge en annen måned i kalenderen for å se tidligere skift."
    : "Når du legger inn skift vil de dukke opp her med full lønnsberegning.";

  return (
    <div className="flex w-full flex-col">
      <div className="h-[calc(100vh-theme(spacing.24)-theme(spacing.8))] flex items-center justify-center -mt-8">
        <div className="w-full">
          <MonthlyEarningsCalendar
            shifts={shifts}
            month={selectedMonth}
            onMonthChange={handleMonthChange}
          />
        </div>
      </div>
      <div className="pb-10">
        {grouped.length === 0 ? (
          <Card className="text-center">
            <CardHeader>
              <CardTitle>{emptyTitle}</CardTitle>
              <CardDescription>{emptyDescription}</CardDescription>
            </CardHeader>
          </Card>
        ) : (
          <div className="flex flex-col gap-8">
            {grouped.map((group) => (
              <section key={group.id} className="space-y-4">
                <Card className="rounded-card border-0">
                  <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3">
                    <div className="flex items-center gap-2 font-medium text-text-primary">
                      <span>{group.label}</span>
                      <svg
                        aria-hidden="true"
                        className="h-4 w-4 text-text-muted"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="1.5"
                      >
                        <path d="m6 9 6 6 6-6" />
                      </svg>
                    </div>
                    <span className="font-semibold text-text-primary">
                      {formatWeekTotal(group.totalGross)}
                    </span>
                  </CardHeader>
                </Card>
                <div className="space-y-4">
                  {group.shifts.map((shift) => (
                    <ShiftCard key={shift.id} shift={shift} />
                  ))}
                </div>
              </section>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
