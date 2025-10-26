"use client";

import { useId, useMemo, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Input } from "@/components/app/Input";
import { TimeInput } from "@/components/app/TimeInput";
import { Button } from "@/components/app/Button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/app/Dialog";
import { createShifts } from "@/app/[locale]/(app)/shifts/add/actions";
import { IconClock } from "@tabler/icons-react";
import { cn } from "@/lib/cn";
import { FreeTierLimitModal } from "./FreeTierLimitModal";
import { checkShiftLimit } from "@/app/[locale]/(app)/shifts/add/_checks/checkShiftLimit";
import { useNavigationFeedback } from "@/components/app/navigation-feedback";
import { useTranslations } from "@/lib/i18n/client";

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
  const { t } = useTranslations();
  const router = useRouter();
  const { navigate } = useNavigationFeedback();
  const [pending, startTransition] = useTransition();

  const [startDate, setStartDate] = useState<string>(() => toLocalISODate(new Date()));
  const [endDate, setEndDate] = useState<string>(() => toLocalISODate(new Date(new Date().setMonth(new Date().getMonth() + 1))));
  const [selectedInterval, setSelectedInterval] = useState<number | null>(1);
  const [customInterval, setCustomInterval] = useState<string>("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const startInputRef = useRef<HTMLInputElement>(null);
  const endInputRef = useRef<HTMLInputElement>(null);
  const idPrefix = useId();
  const startDateId = `${idPrefix}-start-date`;
  const endDateId = `${idPrefix}-end-date`;
  const customIntervalId = `${idPrefix}-interval`;
  const startTimeId = `${idPrefix}-start-time`;
  const endTimeId = `${idPrefix}-end-time`;

  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showLimitModal, setShowLimitModal] = useState(false);
  const [limitModalData, setLimitModalData] = useState<{ existingMonths: string[]; targetMonth: string } | null>(null);

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

  const onConfirm = async () => {
    setError(null);

    try {
      // Extract target month from first date in the series
      const targetMonth = dates[0]?.substring(0, 7); // YYYY-MM
      if (!targetMonth) {
        setError(t.pages.shifts.add.form.couldNotDetermineMonth);
        setOpen(false);
        return;
      }

      // Check if user can add shifts to this month (before transition)
      const limitCheck = await checkShiftLimit(targetMonth);

      if (!limitCheck.allowed && limitCheck.existingMonths) {
        // Close the preview dialog and show limit modal
        setOpen(false);
        setLimitModalData({
          existingMonths: limitCheck.existingMonths,
          targetMonth,
        });
        setShowLimitModal(true);
        return;
      }

      // User is allowed - proceed with shift creation in transition
      setOpen(false);
      startTransition(async () => {
        try {
          const sid = crypto.randomUUID();
          await createShifts({ dates, start, end, seriesId: sid });
          navigate("/shifts");
          router.refresh();
        } catch (e: any) {
          setError(e?.message || t.pages.shifts.add.form.couldNotSaveShift);
        }
      });
    } catch (e: any) {
      setError(e?.message || t.pages.shifts.add.form.couldNotSaveShift);
      setOpen(false);
    }
  };

  const handleDeleteAndProceed = async () => {
    // Called after user deletes shifts in other months
    setError(null);
    startTransition(async () => {
      try {
        const sid = crypto.randomUUID();
        await createShifts({ dates, start, end, seriesId: sid });
        navigate("/shifts");
        router.refresh();
      } catch (e: any) {
        setError(e?.message || t.pages.shifts.add.form.couldNotSaveShift);
      }
    });
  };

  const seriesSummary = useMemo(() => {
    if (dates.length === 0) {
      return t.pages.shifts.add.recurring.selectDatesForSeries;
    }
    const first = dates[0];
    const last = dates[dates.length - 1];
    const hasTimes = /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end);
    const timeRange = hasTimes ? `${start}–${end}` : t.pages.shifts.add.recurring.specifyTime;
    if (dates.length === 1) {
      return t.pages.shifts.add.recurring.seriesWith1Shift
        .replace('{time}', timeRange)
        .replace('{date}', first);
    }
    return t.pages.shifts.add.recurring.seriesWithShifts
      .replace('{count}', dates.length.toString())
      .replace('{first}', first)
      .replace('{last}', last)
      .replace('{time}', timeRange);
  }, [dates, end, start, t]);

  const fieldWrapperClass =
    "block min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner transition hover:border-border";
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
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label htmlFor={startDateId} className={fieldWrapperClass}>
          <span className={fieldLabelClass}>{t.pages.shifts.add.recurring.startDate}</span>
          <Input
            id={startDateId}
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            className="h-10 rounded-xl border-border-subtle bg-transparent text-base text-text-primary"
          />
        </label>
        <label htmlFor={endDateId} className={fieldWrapperClass}>
          <span className={fieldLabelClass}>{t.pages.shifts.add.recurring.endDate}</span>
          <Input
            id={endDateId}
            type="date"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            className="h-10 rounded-xl border-border-subtle bg-transparent text-base text-text-primary"
          />
        </label>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-5">
        {[
          { label: t.pages.shifts.add.recurring.everyWeek, value: 1 },
          { label: t.pages.shifts.add.recurring.every2Weeks, value: 2 },
          { label: t.pages.shifts.add.recurring.every3Weeks, value: 3 },
          { label: t.pages.shifts.add.recurring.every4Weeks, value: 4 },
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
                "flex h-full items-center justify-center rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 text-sm font-medium text-text-secondary shadow-app-sm dark:shadow-app-inner transition hover:border-border hover:text-text-primary focus:outline-none focus-visible:outline-none",
                isActive && "border-brand-gradientMid/60 bg-brand-gradientMid/10 text-text-primary shadow-app"
              )}
            >
              {option.label}
            </button>
          );
        })}

        <label
          htmlFor={customIntervalId}
          className={cn(
            fieldWrapperClass,
            "flex h-full flex-col items-center justify-center gap-2 space-y-0 py-5",
            selectedInterval === null && "border-brand-gradientMid/60 bg-brand-gradientMid/10 text-text-primary shadow-app"
          )}
        >
          <span
            className={cn(
              "text-sm font-medium text-text-secondary",
              selectedInterval === null && "text-text-primary"
            )}
          >
            {t.pages.shifts.add.recurring.every}
          </span>
          <div className="relative w-full max-w-[6rem]">
            <Input
              id={customIntervalId}
              type="text"
              inputMode="numeric"
              pattern="[0-9]*"
              value={customInterval}
              onChange={(e) => {
                const value = e.target.value;
                if (/^\d*$/.test(value)) {
                  setCustomInterval(value);
                  setSelectedInterval(null);
                }
              }}
              className="h-10 w-full rounded-xl border-border-subtle bg-transparent px-3 text-center text-transparent"
              style={{ caretColor: "var(--color-text-primary, #94a3b8)" }}
            />
            <span
              className={cn(
                "pointer-events-none absolute inset-0 flex items-center justify-center text-sm text-text-muted",
                selectedInterval === null && "text-text-primary"
              )}
            >
              {customInterval ? `${customInterval}. ${t.pages.shifts.add.recurring.week}` : `x. ${t.pages.shifts.add.recurring.week}`}
            </span>
          </div>
        </label>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label htmlFor={startTimeId} className={fieldWrapperClass}>
          <span className={fieldLabelClass}>{t.pages.shifts.add.form.start}</span>
          <div className="flex min-w-0 items-center gap-2">
            <TimeInput
              id={startTimeId}
              ref={startInputRef}
              value={start}
              onChange={setStart}
              onComplete={() => endInputRef.current?.focus()}
            />
            <button
              type="button"
              onClick={() => openNativePicker(startInputRef.current)}
              className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-xl border border-border-subtle bg-surface-secondary/70 text-text-muted transition hover:border-border hover:text-text-primary focus:outline-none focus-visible:outline-none"
              aria-label={t.pages.shifts.add.form.selectStartTime}
            >
              <IconClock className="h-5 w-5" stroke={1.5} />
            </button>
          </div>
        </label>
        <label htmlFor={endTimeId} className={fieldWrapperClass}>
          <span className={fieldLabelClass}>{t.pages.shifts.add.form.end}</span>
          <div className="flex min-w-0 items-center gap-2">
            <TimeInput
              id={endTimeId}
              ref={endInputRef}
              value={end}
              onChange={setEnd}
            />
            <button
              type="button"
              onClick={() => openNativePicker(endInputRef.current)}
              className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-xl border border-border-subtle bg-surface-secondary/70 text-text-muted transition hover:border-border hover:text-text-primary focus:outline-none focus-visible:outline-none"
              aria-label={t.pages.shifts.add.form.selectEndTime}
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
          {t.pages.shifts.add.recurring.previewSeries.replace('{count}', (dates.length || 0).toString())}
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md rounded-3xl border border-border-subtle bg-surface-primary/95 shadow-app-lg">
          <DialogHeader>
            <DialogTitle>{t.pages.shifts.add.recurring.confirmSeries}</DialogTitle>
            <DialogDescription>
              {t.pages.shifts.add.recurring.confirmingSeriesDescription.replace('{count}', dates.length.toString())}
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
                {t.pages.shifts.add.recurring.andMore.replace('{count}', (dates.length - 20).toString())}
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
              {t.pages.shifts.add.recurring.cancel}
            </Button>
            <Button
              type="button"
              onClick={onConfirm}
              loading={pending}
              className="rounded-xl bg-brand-gradientMid px-5 py-2 font-semibold text-text-inverse shadow-app transition hover:bg-brand-gradientEnd"
            >
              {t.pages.shifts.add.recurring.confirm}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

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
