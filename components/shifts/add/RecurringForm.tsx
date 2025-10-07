"use client";

import { useMemo, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Input } from "@/components/app/Input";
import { Button } from "@/components/app/Button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/app/Dialog";
import { createShifts } from "../../../app/(app)/shifts/add/actions";
import { IconClock } from "@tabler/icons-react";
import { cn } from "@/lib/cn";

function toLocalISODate(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function parseISODate(s: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const [y, m, d] = s.split("-").map((n) => parseInt(n, 10));
  const dt = new Date(y, m - 1, d);
  // Basic guard that the date stayed correct
  if (dt.getFullYear() !== y || dt.getMonth() !== m - 1 || dt.getDate() !== d) return null;
  return dt;
}

export default function RecurringForm() {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  const [startDate, setStartDate] = useState<string>(() => toLocalISODate(new Date()));
  const [endDate, setEndDate] = useState<string>(() => toLocalISODate(new Date(new Date().setMonth(new Date().getMonth() + 1))));
  const [selectedInterval, setSelectedInterval] = useState<number | null>(1);
  const [customInterval, setCustomInterval] = useState<string>("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const startInputRef = useRef<HTMLInputElement>(null);
  const endInputRef = useRef<HTMLInputElement>(null);

  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const parsedCustomInterval = useMemo(() => {
    const parsed = parseInt(customInterval, 10);
    if (Number.isNaN(parsed) || parsed <= 0) {
      return null;
    }
    return parsed;
  }, [customInterval]);

  const effectiveInterval = useMemo(() => {
    return Math.max(1, selectedInterval ?? parsedCustomInterval ?? 1);
  }, [parsedCustomInterval, selectedInterval]);

  const dates = useMemo(() => {
    const out: string[] = [];
    const s = parseISODate(startDate);
    const e = parseISODate(endDate);
    const n = Math.max(1, Math.floor(effectiveInterval || 1));
    if (!s || !e || s > e) return out;
    let cur = new Date(s);
    while (cur <= e) {
      out.push(toLocalISODate(cur));
      cur = new Date(cur);
      cur.setDate(cur.getDate() + 7 * n);
    }
    return out;
  }, [startDate, endDate, effectiveInterval]);

  const canSubmit = dates.length > 0 && /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end);

  const onPreview = () => {
    if (!canSubmit) return;
    setError(null);
    setOpen(true);
  };

  const onConfirm = () => {
    setError(null);
    startTransition(async () => {
      try {
        const sid = crypto.randomUUID();
        await createShifts({ dates, start, end, seriesId: sid });
        router.push("/shifts");
        router.refresh();
      } catch (e: any) {
        setError(e?.message || "Kunne ikke lagre skift");
      } finally {
        setOpen(false);
      }
    });
  };

  const seriesSummary = useMemo(() => {
    if (dates.length === 0) {
      return "Velg start- og sluttdato for å se hvilke uker som inngår i serien.";
    }
    const first = dates[0];
    const last = dates[dates.length - 1];
    const hasTimes = /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end);
    const timeRange = hasTimes ? `${start}–${end}` : "angi tidspunkt for vakten";
    if (dates.length === 1) {
      return `Serie med 1 skift (${timeRange}) på ${first}.`;
    }
    return `Serie med ${dates.length} skift fra ${first} til ${last} · ${timeRange}.`;
  }, [dates, end, start]);

  const fieldWrapperClass =
    "block space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner transition hover:border-border";
  const fieldLabelClass =
    "text-xs font-semibold uppercase tracking-[0.1em] text-text-muted";

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
    <div className="space-y-6">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className={fieldWrapperClass}>
          <span className={fieldLabelClass}>Startdato</span>
          <Input
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            className="h-10 rounded-xl border-border-subtle bg-transparent text-base text-text-primary"
          />
        </label>
        <label className={fieldWrapperClass}>
          <span className={fieldLabelClass}>Sluttdato</span>
          <Input
            type="date"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            className="h-10 rounded-xl border-border-subtle bg-transparent text-base text-text-primary"
          />
        </label>
      </div>

      <div className="grid gap-3 sm:grid-cols-5">
        {[
          { label: "Hver uke", value: 1 },
          { label: "Hver 2. uke", value: 2 },
          { label: "Hver 3. uke", value: 3 },
          { label: "Hver 4. uke", value: 4 },
        ].map((option) => {
          const isActive = selectedInterval === option.value;
          return (
            <button
              key={option.value}
              type="button"
              onClick={() => {
                setSelectedInterval(option.value);
                setCustomInterval("");
              }}
              className={cn(
                "flex h-full items-center justify-center rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 text-sm font-medium text-text-secondary shadow-app-inner transition hover:border-border hover:text-text-primary focus:outline-none focus-visible:outline-none",
                isActive && "border-brand-gradientMid/60 bg-brand-gradientMid/10 text-text-primary shadow-app"
              )}
            >
              {option.label}
            </button>
          );
        })}

        <label
          className={cn(
            fieldWrapperClass,
            "h-full flex items-center justify-center",
            selectedInterval === null && "border-brand-gradientMid/60 bg-brand-gradientMid/10 text-text-primary shadow-app"
          )}
        >
          <Input
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            value={customInterval}
            placeholder="Hver x. uke"
            onChange={(e) => {
              const value = e.target.value;
              if (/^\d*$/.test(value)) {
                setCustomInterval(value);
                setSelectedInterval(null);
              }
            }}
            className="h-10 w-auto min-w-[7rem] max-w-full rounded-xl border-border-subtle bg-transparent px-3 text-center text-base text-text-primary"
          />
        </label>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <label className={fieldWrapperClass}>
          <span className={fieldLabelClass}>Start</span>
          <div className="relative">
            <Input
              ref={startInputRef}
              type="time"
              step={900}
              value={start}
              onChange={(e) => setStart(e.target.value)}
              className="h-10 rounded-xl border-border-subtle bg-transparent pr-12 text-base text-text-primary"
            />
            <button
              type="button"
              onClick={() => openNativePicker(startInputRef.current)}
              className="absolute inset-y-0 right-3 flex items-center text-text-muted transition hover:text-text-primary focus:outline-none"
              aria-label="Velg starttid"
            >
              <IconClock className="h-5 w-5" stroke={1.5} />
            </button>
          </div>
        </label>
        <label className={fieldWrapperClass}>
          <span className={fieldLabelClass}>Slutt</span>
          <div className="relative">
            <Input
              ref={endInputRef}
              type="time"
              step={900}
              value={end}
              onChange={(e) => setEnd(e.target.value)}
              className="h-10 rounded-xl border-border-subtle bg-transparent pr-12 text-base text-text-primary"
            />
            <button
              type="button"
              onClick={() => openNativePicker(endInputRef.current)}
              className="absolute inset-y-0 right-3 flex items-center text-text-muted transition hover:text-text-primary focus:outline-none"
              aria-label="Velg sluttid"
            >
              <IconClock className="h-5 w-5" stroke={1.5} />
            </button>
          </div>
        </label>
      </div>

      <div className="rounded-2xl border border-border-subtle bg-surface-secondary/70 px-4 py-3 text-sm text-text-secondary shadow-app-inner">
        {seriesSummary}
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
          onClick={onPreview}
          disabled={!canSubmit}
          loading={pending}
          className="rounded-2xl bg-brand-gradientMid px-6 py-3 text-base font-semibold text-text-inverse shadow-app transition hover:bg-brand-gradientEnd"
        >
          Forhåndsvis serie ({dates.length || 0})
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md rounded-3xl border border-border-subtle bg-surface-primary/95 shadow-app-lg">
          <DialogHeader>
            <DialogTitle>Bekreft serie</DialogTitle>
            <DialogDescription>
              Du er i ferd med å opprette {dates.length} skift.
            </DialogDescription>
          </DialogHeader>
          <div className="max-h-56 space-y-2 overflow-auto rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 text-sm text-text-primary shadow-app-inner">
            {dates.slice(0, 20).map((d) => (
              <div key={d} className="flex items-center justify-between gap-2 rounded-xl bg-surface-primary/70 px-3 py-2">
                <span className="font-medium">{d}</span>
                <span className="text-sm text-text-secondary">
                  {start}–{end}
                </span>
              </div>
            ))}
            {dates.length > 20 && (
              <div className="rounded-xl bg-surface-primary/60 px-3 py-2 text-center text-sm text-text-muted shadow-app-inner">
                …og {dates.length - 20} til
              </div>
            )}
          </div>
          <DialogFooter className="gap-2 pt-4">
            <Button
              type="button"
              variant="ghost"
              onClick={() => setOpen(false)}
              className="rounded-xl px-4 py-2 text-text-secondary hover:text-text-primary"
            >
              Avbryt
            </Button>
            <Button
              type="button"
              onClick={onConfirm}
              loading={pending}
              className="rounded-xl bg-brand-gradientMid px-5 py-2 font-semibold text-text-inverse shadow-app transition hover:bg-brand-gradientEnd"
            >
              Bekreft
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
