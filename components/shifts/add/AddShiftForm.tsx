"use client";

import { useMemo, useState, useTransition, useEffect, useRef } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import { SelectDatesCalendar } from "@/components/app/SelectDatesCalendar";
import type { ISODate } from "@/components/calendar/calendar.utils";
import { createShifts } from "../../../app/(app)/shifts/add/actions";
import RecurringForm from "./RecurringForm";
import { MonthPicker } from "@/components/app/MonthPicker";
import { cn } from "@/lib/cn";
import { IconClock } from "@tabler/icons-react";
import { FreeTierLimitModal } from "./FreeTierLimitModal";
import { checkShiftLimit } from "../../../app/(app)/shifts/add/_checks/checkShiftLimit";

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
  const startInputRef = useRef<HTMLInputElement>(null);
  const endInputRef = useRef<HTMLInputElement>(null);
  const [showLimitModal, setShowLimitModal] = useState(false);
  const [limitModalData, setLimitModalData] = useState<{ existingMonths: string[]; targetMonth: string } | null>(null);

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
        // Extract target month from first selected date
        const targetMonth = isoDates[0]?.substring(0, 7); // YYYY-MM
        if (!targetMonth) {
          setError("Kunne ikke bestemme måneden");
          return;
        }

        // Check if user can add shifts to this month
        const limitCheck = await checkShiftLimit(targetMonth);

        if (!limitCheck.allowed && limitCheck.existingMonths) {
          // Show modal with options to upgrade or delete
          setLimitModalData({
            existingMonths: limitCheck.existingMonths,
            targetMonth,
          });
          setShowLimitModal(true);
          return;
        }

        // User is allowed - proceed with shift creation
        await createShifts({ dates: isoDates, start, end });
        // Navigate and refresh to show new data immediately
        router.push("/shifts");
        router.refresh();
      } catch (e: any) {
        setError(e?.message || "Kunne ikke lagre skift");
      }
    });
  };

  const handleDeleteAndProceed = async () => {
    // Called after user deletes shifts in other months
    setError(null);
    startTransition(async () => {
      try {
        await createShifts({ dates: isoDates, start, end });
        router.push("/shifts");
        router.refresh();
      } catch (e: any) {
        setError(e?.message || "Kunne ikke lagre skift");
      }
    });
  };

  const selectedSummary = useMemo(() => {
    if (dates.length === 0) return "Velg en eller flere datoer i kalenderen.";
    const sorted = [...dates].sort((a, b) => a.getTime() - b.getTime());
    const first = toLocalISODate(sorted[0]);
    const last = toLocalISODate(sorted[sorted.length - 1]);
    if (sorted.length === 1) return `Valgt dato: ${first}`;
    return `${sorted.length} datoer valgt · ${first} – ${last}`;
  }, [dates]);

  const openNativePicker = (input: HTMLInputElement | null) => {
    if (!input) return;
    const picker = (input as unknown as { showPicker?: () => void }).showPicker;
    if (typeof picker === "function") {
      picker.call(input);
    } else {
      input.focus();
    }
  };

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-6 pb-24">
      <div className="flex flex-col gap-4">
        <div className="space-y-1">
          <span className="text-xs font-semibold uppercase tracking-[0.2em] text-brand-highlight">
            Skiftplanlegging
          </span>
          <div className="flex items-center justify-between gap-3">
            <h1 className="whitespace-nowrap text-2xl font-semibold text-text-primary sm:text-3xl">
              Legg til skift
            </h1>
            <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 shadow-app-sm dark:shadow-app-inner flex-shrink-0">
              <Button
                type="button"
                variant="ghost"
                aria-pressed={mode === "single"}
                onClick={() => setMode("single")}
                className={cn(
                  "h-9 rounded-full px-4 text-sm transition-all whitespace-nowrap",
                  mode === "single"
                    ? "bg-brand-gradientMid text-text-inverse shadow-app"
                    : "text-text-secondary hover:text-text-primary"
                )}
              >
                Enkel
              </Button>
              <Button
                type="button"
                variant="ghost"
                aria-pressed={mode === "recurring"}
                onClick={() => setMode("recurring")}
                className={cn(
                  "h-9 rounded-full px-4 text-sm transition-all whitespace-nowrap",
                  mode === "recurring"
                    ? "bg-brand-gradientMid text-text-inverse shadow-app"
                    : "text-text-secondary hover:text-text-primary"
                )}
              >
                Serie
              </Button>
            </div>
          </div>
        </div>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <p className="text-sm text-text-secondary">
            {mode === "single"
              ? "Velg én eller flere datoer og angi tidsrommet for vakten."
              : "Angi start- og sluttdato, intervall og tidsrom for gjentakende vakter."}
          </p>
        </div>
      </div>
      <div className="space-y-6">
        {mode === "single" ? (
          <>
            <div className="flex flex-wrap items-center justify-between gap-4">
              <MonthPicker
                month={month}
                onPreviousMonth={() =>
                  setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))
                }
                onNextMonth={() =>
                  setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))
                }
              />
              <span className="rounded-full bg-surface-secondary/80 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-text-muted">
                {month.getFullYear()}
              </span>
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

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <label className="block min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner transition hover:border-border">
                <span className="text-xs font-semibold uppercase tracking-[0.1em] text-text-muted">
                  Start
                </span>
                <div className="flex min-w-0 items-center gap-2">
                  <Input
                    ref={startInputRef}
                    type="time"
                    step={900}
                    value={start}
                    onChange={(e) => setStart(e.target.value)}
                    className="h-10 flex-1 rounded-xl border-border-subtle bg-transparent text-base text-text-primary"
                  />
                  <button
                    type="button"
                    onClick={() => openNativePicker(startInputRef.current)}
                    className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-xl border border-border-subtle bg-surface-secondary/70 text-text-muted transition hover:border-border hover:text-text-primary focus:outline-none focus-visible:outline-none"
                    aria-label="Velg starttid"
                  >
                    <IconClock className="h-5 w-5" stroke={1.5} />
                  </button>
                </div>
              </label>
              <label className="block min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner transition hover:border-border">
                <span className="text-xs font-semibold uppercase tracking-[0.1em] text-text-muted">
                  Slutt
                </span>
                <div className="flex min-w-0 items-center gap-2">
                  <Input
                    ref={endInputRef}
                    type="time"
                    step={900}
                    value={end}
                    onChange={(e) => setEnd(e.target.value)}
                    className="h-10 flex-1 rounded-xl border-border-subtle bg-transparent text-base text-text-primary"
                  />
                  <button
                    type="button"
                    onClick={() => openNativePicker(endInputRef.current)}
                    className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-xl border border-border-subtle bg-surface-secondary/70 text-text-muted transition hover:border-border hover:text-text-primary focus:outline-none focus-visible:outline-none"
                    aria-label="Velg sluttid"
                  >
                    <IconClock className="h-5 w-5" stroke={1.5} />
                  </button>
                </div>
              </label>
            </div>

            <div className="rounded-2xl border border-border-subtle bg-surface-secondary/70 px-4 py-3 text-sm text-text-secondary shadow-app-inner">
              {selectedSummary}
            </div>

            {error && (
              <div
                className="rounded-2xl border border-error/30 bg-error-subtle px-4 py-3 text-sm font-medium text-error shadow-app-inner"
                role="alert"
              >
                {error}
              </div>
            )}

            <div className="flex justify-center">
              <Button
                onClick={onSubmit}
                disabled={!canSubmit}
                loading={pending}
                className="rounded-2xl bg-brand-gradientMid px-6 py-3 text-base font-semibold text-text-inverse shadow-app transition hover:bg-brand-gradientEnd"
              >
                Legg til {dates.length || 0} skift
              </Button>
            </div>
          </>
        ) : (
          <RecurringForm />
        )}
      </div>

      {/* Free tier limitation modal */}
      {limitModalData && (
        <FreeTierLimitModal
          open={showLimitModal}
          onOpenChange={setShowLimitModal}
          existingMonths={limitModalData.existingMonths}
          targetMonth={limitModalData.targetMonth}
          onDeleteComplete={handleDeleteAndProceed}
        />
      )}
    </div>
  );
}
