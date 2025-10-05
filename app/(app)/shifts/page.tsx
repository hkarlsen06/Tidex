import { redirect } from "next/navigation";

import ShiftCard from "@/components/app/ShiftCard";
import { getComputedShifts } from "./_data/getShifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ShiftWithComputations } from "@/lib/payroll";

type WeekGroup = {
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
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNumber = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
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

  return groups;
}

function formatWeekTotal(value: number) {
  return `${currencyFormatter.format(Math.round(value))} kr`;
}

export default async function ShiftsPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const shifts = await getComputedShifts(user.id);
  const grouped = groupByWeek(shifts);

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-10">
      {grouped.length === 0 ? (
        <div className="rounded-3xl border border-border-subtle/60 bg-surface-secondary/40 px-8 py-12 text-center text-text-secondary">
          <p className="text-lg font-medium text-text-primary">Ingen skift registrert ennå</p>
          <p className="mt-2">
            Når du legger inn skift vil de dukke opp her med full lønnsberegning.
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-8">
          {grouped.map((group) => (
            <section key={group.id} className="space-y-4">
              <header className="flex items-center justify-between rounded-2xl bg-surface-primary/60 px-4 py-3 text-sm text-text-secondary">
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
                <span className="text-text-primary">{formatWeekTotal(group.totalGross)}</span>
              </header>
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
  );
}
