"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Card, CardHeader, CardTitle } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import { SelectDatesCalendar } from "@/components/app/SelectDatesCalendar";
import { createShifts } from "./actions";

function startOfMonth(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function toLocalISODate(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export default function AddShiftForm() {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [month, setMonth] = useState<Date>(() => startOfMonth(new Date()));
  const [dates, setDates] = useState<Date[]>([]);
  const [start, setStart] = useState("08:00");
  const [end, setEnd] = useState("16:00");
  const [error, setError] = useState<string | null>(null);

  const canSubmit = dates.length > 0 && /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end);

  const isoDates = useMemo(() => dates.map(toLocalISODate), [dates]);

  const onSubmit = () => {
    if (!canSubmit) return;
    setError(null);
    startTransition(async () => {
      try {
        await createShifts({ dates: isoDates, start, end });
        // Navigate and refresh to show new data immediately
        router.push("/shifts");
        router.refresh();
      } catch (e: any) {
        setError(e?.message || "Kunne ikke lagre skift");
      }
    });
  };

  return (
    <div className="py-6">
      <Card className="rounded-card">
        <CardHeader>
          <CardTitle>Legg til skift</CardTitle>
        </CardHeader>
        <div className="px-4 pb-6 space-y-4">
          <SelectDatesCalendar
            month={month}
            onMonthChange={setMonth}
            selected={dates}
            onSelectedChange={setDates}
          />

          <div className="grid grid-cols-2 gap-3">
            <label className="space-y-1">
              <span className="text-sm text-text-secondary">Start</span>
              <Input
                type="time"
                step={900}
                value={start}
                onChange={(e) => setStart(e.target.value)}
              />
            </label>
            <label className="space-y-1">
              <span className="text-sm text-text-secondary">Slutt</span>
              <Input
                type="time"
                step={900}
                value={end}
                onChange={(e) => setEnd(e.target.value)}
              />
            </label>
          </div>

          {error && (
            <div className="text-sm text-error" role="alert">
              {error}
            </div>
          )}

          <Button onClick={onSubmit} disabled={!canSubmit} loading={pending}>
            Legg til {dates.length || 0} skift
          </Button>
        </div>
      </Card>
    </div>
  );
}

