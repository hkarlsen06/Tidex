"use client";

import { useMemo, useState, useTransition, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import { SelectDatesCalendar } from "@/components/app/SelectDatesCalendar";
import type { ISODate } from "@/components/calendar/calendar.utils";
import { createShifts } from "../../app/(app)/shifts/add/actions";
import RecurringForm from "../../app/(app)/shifts/add/RecurringForm";
import { MonthPicker } from "@/components/app/MonthPicker";

type ExistingShift = {
  shift_date: string; // YYYY-MM-DD
  start_time: string; // HH:mm
  end_time: string; // HH:mm
};

function startOfMonth(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function toLocalISODate(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(":").map((n) => parseInt(n, 10));
  return h * 60 + m;
}

function addDaysISO(iso: string, days: number): string {
  const d = new Date(iso + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function overlaps(aStart: number, aEnd: number, bStart: number, bEnd: number) {
  return aStart < bEnd && bStart < aEnd;
}

type Props = {
  existingShifts: ExistingShift[];
};

export default function AddShiftForm({ existingShifts }: Props) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [pending, startTransition] = useTransition();
  const [mode, setMode] = useState<"single" | "recurring">("single");
  const [month, setMonth] = useState<Date>(() => startOfMonth(new Date()));
  const [dates, setDates] = useState<Date[]>([]);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [error, setError] = useState<string | null>(null);

  const canSubmit = dates.length > 0 && /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end);

  const isoDates = useMemo(() => dates.map(toLocalISODate), [dates]);

  // Build interval map from existing shifts, expanding cross-midnight parts onto next day
  const intervalMap = useMemo(() => {
    const map = new Map<string, Array<[number, number]>>();
    for (const s of existingShifts) {
      const sMin = toMinutes(s.start_time);
      const eMin = toMinutes(s.end_time);
      if (eMin > sMin) {
        const arr = map.get(s.shift_date) ?? [];
        arr.push([sMin, eMin]);
        map.set(s.shift_date, arr);
      } else {
        const arr1 = map.get(s.shift_date) ?? [];
        arr1.push([sMin, 24 * 60]);
        map.set(s.shift_date, arr1);
        const next = addDaysISO(s.shift_date, 1);
        const arr2 = map.get(next) ?? [];
        arr2.push([0, eMin]);
        map.set(next, arr2);
      }
    }
    return map;
  }, [existingShifts]);

  const hasShiftDates = useMemo(
    () => new Set<ISODate>(Array.from(intervalMap.keys()) as ISODate[]),
    [intervalMap]
  );

  const conflictDates = useMemo(() => {
    const result = new Set<ISODate>();
    const startMin = toMinutes(start);
    const endMin = toMinutes(end);
    const isCross = endMin <= startMin;
    intervalMap.forEach((intervals, iso) => {
      if (!intervals || intervals.length === 0) return;
      if (!isCross) {
        if (intervals.some(([a, b]) => overlaps(a, b, startMin, endMin))) {
          result.add(iso as ISODate);
        }
      } else {
        if (intervals.some(([a, b]) => overlaps(a, b, startMin, 24 * 60))) {
          result.add(iso as ISODate);
        }
        if (intervals.some(([a, b]) => overlaps(a, b, 0, endMin))) {
          result.add(iso as ISODate);
        }
      }
    });
    return result;
  }, [intervalMap, start, end]);

  // Prefill a date from query param `?date=YYYY-MM-DD`
  useEffect(() => {
    const dateParam = searchParams.get("date");
    if (dateParam && /^\d{4}-\d{2}-\d{2}$/.test(dateParam)) {
      const [y, m, d] = dateParam.split("-").map((n) => parseInt(n, 10));
      const dt = new Date(y, m - 1, d);
      if (
        dt.getFullYear() === y &&
        dt.getMonth() === m - 1 &&
        dt.getDate() === d
      ) {
        setMonth(startOfMonth(dt));
        setDates([dt]);
      }
    }
    // run once on mount for initial URL
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
    <div>
      <div className="space-y-4">
          <h1>Legg til skift</h1>
          <div className="flex items-center gap-2">
            <Button
              type="button"
              onClick={() => setMode("single")}
              className={mode === "single" ? "" : "opacity-60"}
            >
              Enkel
            </Button>
            <Button
              type="button"
              onClick={() => setMode("recurring")}
              className={mode === "recurring" ? "" : "opacity-60"}
            >
              Serie
            </Button>
          </div>

          {mode === "single" ? (
            <>
              <div className="flex items-center justify-between">
                <MonthPicker
                  month={month}
                  onPreviousMonth={() =>
                    setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))
                  }
                  onNextMonth={() =>
                    setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))
                  }
                />
                <span className="font-medium text-text-muted">{month.getFullYear()}</span>
              </div>
              <SelectDatesCalendar
                month={month}
                onMonthChange={setMonth}
                selected={dates}
                onSelectedChange={setDates}
                hasShiftDates={hasShiftDates}
                conflictDates={conflictDates}
                hideCaptionNav
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
            </>
          ) : (
            <>
              <RecurringForm />
            </>
          )}
      </div>
    </div>
  );
}
