"use client";

import { useMemo, useState, useCallback, useTransition, useRef, useEffect } from "react";
import { useRouter } from "next/navigation";

import ShiftCard from "@/components/app/ShiftCard";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/app/Card";
import { MonthlyEarningsCalendar } from "./MonthlyEarningsCalendar";
import { ShiftWithComputations } from "@/lib/payroll";
import ShiftDetails from "@/components/shifts/ShiftDetails";
import { deleteShift } from "@/app/(app)/shifts/_actions/deleteShift";
import { useNavigationFeedback } from "@/components/app/navigation-feedback";

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
  defaultView?: string;
};

export function ShiftsView({ shifts, defaultView = "calendar" }: ShiftsViewProps) {
  const router = useRouter();
  const { navigate } = useNavigationFeedback();
  const [pending, startTransition] = useTransition();
  const [selectedMonth, setSelectedMonth] = useState(() => startOfMonth(new Date()));
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [selectedShift, setSelectedShift] = useState<ShiftWithComputations | null>(null);
  const shiftsListRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to shifts list if defaultView is "list"
  useEffect(() => {
    if (defaultView === "list" && shiftsListRef.current) {
      const headerHeight = 96; // Height of TopHeader (theme(spacing.24) = 96px)
      const offset = 32; // Additional spacing (theme(spacing.8) = 32px)
      const targetPosition = shiftsListRef.current.offsetTop - headerHeight - offset;

      window.scrollTo({
        top: targetPosition,
        behavior: "instant"
      });
    }
  }, [defaultView]);

  const handleMonthChange = useCallback((month: Date) => {
    setSelectedMonth(startOfMonth(month));
  }, []);

  const handleDayClick = useCallback(
    (iso: string, hasShifts: boolean) => {
      if (hasShifts) {
        const match = shifts.find((s) => s.shift_date === iso);
        if (match) {
          setSelectedShift(match);
          setDetailsOpen(true);
          return;
        }
      }
      navigate(`/shifts/add?date=${encodeURIComponent(iso)}`);
    },
    [navigate, shifts]
  );

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
    <>
    <div className="flex w-full flex-col">
      <div className="h-[calc(100vh-theme(spacing.24)-theme(spacing.8))] flex items-center justify-center -mt-8">
        <div className="w-full">
          <MonthlyEarningsCalendar
            shifts={shifts}
            month={selectedMonth}
            onMonthChange={handleMonthChange}
            onDayClick={handleDayClick}
          />
        </div>
      </div>
      <div ref={shiftsListRef} className="pb-10">
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
                    <ShiftCard
                      key={shift.id}
                      shift={shift}
                      onClick={() => {
                        setSelectedShift(shift);
                        setDetailsOpen(true);
                      }}
                    />
                  ))}
                </div>
              </section>
            ))}
          </div>
        )}
      </div>
    </div>
    <ShiftDetails
      isOpen={detailsOpen}
      shift={selectedShift}
      onClose={() => {
        setDetailsOpen(false);
        setSelectedShift(null);
      }}
      isDeleting={pending}
      onDelete={(id) => {
        startTransition(async () => {
          try {
            await deleteShift(id);
            setDetailsOpen(false);
            setSelectedShift(null);
            router.refresh();
          } catch (error) {
            console.error("Failed to delete shift", error);
          }
        });
      }}
    />
    </>
  );
}
