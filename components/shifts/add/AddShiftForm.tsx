"use client";

import { useMemo, useState, useEffect, useRef, useCallback, useId } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "@/components/app/Button";
import { TimeInput } from "@/components/app/TimeInput";
import { SelectDatesCalendar } from "@/components/app/SelectDatesCalendar";
import type { ISODate } from "@/components/app/calendar-utils";
import { computeShift, type UserSettings, type SupplementRule, type WageSnapshot } from "@/lib/payroll";
import RecurringForm from "./RecurringForm";
import { MonthPicker } from "@/components/app/MonthPicker";
import { cn } from "@/lib/cn";
import { Clock } from "lucide-react";
import { FreeTierLimitModal } from "./FreeTierLimitModal";
import { checkShiftLimit } from "@/app/[locale]/(app)/shifts/add/_checks/checkShiftLimit";
import { useNavigationFeedback } from "@/components/app/navigation-feedback";
import { useMonth } from "@/components/app/MonthContext";
import { useTranslations, useLocale } from "@/lib/i18n/client";
import { useOnlineStatus } from "@/lib/hooks/useOnlineStatus";
import { useAddShiftForm } from "@/lib/contexts/AddShiftFormContext";

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

function monthKeyFromDate(date: Date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  return `${y}-${m}`;
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
  userSettings: UserSettings;
  presetRules: SupplementRule[];
  wageSnapshots: WageSnapshot[];
};

export default function AddShiftForm({ existingShifts, userSettings, presetRules, wageSnapshots }: Props) {
  const { t } = useTranslations();
  const locale = useLocale();
  const _router = useRouter();
  const { navigate } = useNavigationFeedback();
  const searchParams = useSearchParams();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [mode, setMode] = useState<"single" | "recurring">("single");
  const { selectedMonth: month, setSelectedMonth: setMonth, goToPreviousMonth, goToNextMonth, direction, isHydrated } = useMonth();
  const [dates, setDates] = useState<Date[]>([]);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [error, setError] = useState<string | null>(null);
  const startInputRef = useRef<HTMLInputElement>(null);
  const endInputRef = useRef<HTMLInputElement>(null);
  const startTimeId = useId();
  const endTimeId = useId();
  const [showLimitModal, setShowLimitModal] = useState(false);
  const [limitModalData, setLimitModalData] = useState<{ existingMonths: string[]; targetMonth: string } | null>(null);
  const [isFreeTier, setIsFreeTier] = useState<boolean | null>(null);
  const [showMultiMonthWarning, setShowMultiMonthWarning] = useState(false);
  const limitStatusLoadingRef = useRef(false);
  const isOffline = useOnlineStatus();
  const { registerForm, unregisterForm } = useAddShiftForm();

  const canSubmit = !isOffline && dates.length > 0 && /^\d{2}:\d{2}$/.test(start) && /^\d{2}:\d{2}$/.test(end);

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

  // Ref to hold the latest onSubmit function for the context
  const onSubmitRef = useRef<() => void>(() => {});

  // Reset submitting state when component mounts (e.g., user navigates back)
  useEffect(() => {
    setIsSubmitting(false);
  }, []);

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

  // Handle limit error from optimistic navigation redirect
  useEffect(() => {
    const limitError = searchParams.get("limitError");
    const targetMonth = searchParams.get("targetMonth");
    const existingMonthsParam = searchParams.get("existingMonths");

    if (limitError === "true" && targetMonth && existingMonthsParam) {
      const existingMonths = existingMonthsParam.split(",").filter(Boolean);
      setIsFreeTier(true);
      setLimitModalData({ existingMonths, targetMonth });
      setShowLimitModal(true);

      // Clear URL params
      const url = new URL(window.location.href);
      url.searchParams.delete("limitError");
      url.searchParams.delete("targetMonth");
      url.searchParams.delete("existingMonths");
      window.history.replaceState({}, "", url.toString());
    }
  }, [searchParams]);

  const ensureLimitStatus = useCallback(
    async (targetMonth: string) => {
      if (isFreeTier !== null || limitStatusLoadingRef.current) {
        return;
      }

      limitStatusLoadingRef.current = true;
      try {
        const status = await checkShiftLimit(targetMonth);
        setIsFreeTier(status.isFreeTier);
      } catch (err) {
        console.error("Kunne ikke sjekke abonnementstatus:", err);
      } finally {
        limitStatusLoadingRef.current = false;
      }
    },
    [isFreeTier]
  );

  useEffect(() => {
    const initialMonthKey = monthKeyFromDate(month);
    void ensureLimitStatus(initialMonthKey);
  }, [month, ensureLimitStatus]);

  const handleSelectedChange = useCallback(
    (nextDates: Date[]) => {
      if (nextDates.length > 0) {
        const firstMonthKey = monthKeyFromDate(nextDates[0]);
        void ensureLimitStatus(firstMonthKey);
      }

      if (isFreeTier) {
        const uniqueMonths = new Set(nextDates.map(monthKeyFromDate));
        if (uniqueMonths.size > 1) {
          setShowMultiMonthWarning(true);
          return;
        }
      }

      setShowMultiMonthWarning(false);
      setDates(nextDates);
    },
    [ensureLimitStatus, isFreeTier]
  );

  const onSubmit = async () => {
    if (!canSubmit || isSubmitting) return;
    setIsSubmitting(true);
    setError(null);

    // Extract target month from first selected date
    const targetMonth = isoDates[0]?.substring(0, 7); // YYYY-MM
    if (!targetMonth) {
      setError(t.pages.shifts.add.form.couldNotDetermineMonth);
      setIsSubmitting(false);
      return;
    }

    // For free tier users, we need to check the limit before proceeding
    // But we can do this check optimistically - navigate first, validate in background
    if (isFreeTier === true) {
      try {
        const limitCheck = await checkShiftLimit(targetMonth);
        setIsFreeTier(limitCheck.isFreeTier);

        if (!limitCheck.allowed && limitCheck.existingMonths) {
          // Show modal with options to upgrade or delete
          setLimitModalData({
            existingMonths: limitCheck.existingMonths,
            targetMonth,
          });
          setShowLimitModal(true);
          setIsSubmitting(false);
          return;
        }
      } catch (e: any) {
        setError(e?.message || t.pages.shifts.add.form.couldNotSaveShift);
        setIsSubmitting(false);
        return;
      }
    }

    // OPTIMISTIC: Navigate immediately with shift data encoded in URL
    // The shifts page will show optimistic shifts AND trigger the server action
    const optimisticData = encodeURIComponent(JSON.stringify({
      dates: isoDates,
      start,
      end,
      // Include metadata for the shifts page to handle the save
      _save: true,
      _targetMonth: targetMonth,
      _checkLimit: isFreeTier !== true, // Only check limit if we haven't already
    }));

    // Clear form state immediately for snappy feel
    setDates([]);
    setStart("");
    setEnd("");
    setError(null);

    // Navigate immediately - shifts page will handle both display AND saving
    navigate(`/${locale}/shifts?optimistic=${optimisticData}`);
  };

  // Keep the ref updated with the latest onSubmit function
  onSubmitRef.current = onSubmit;

  // Register form with context for NavBar to trigger submission (only for single mode)
  useEffect(() => {
    if (mode === "single") {
      registerForm({
        submit: () => onSubmitRef.current(),
        canSubmit,
        isSubmitting,
      });
    } else {
      // Unregister when in recurring mode
      unregisterForm();
    }

    return () => {
      unregisterForm();
    };
  }, [mode, canSubmit, isSubmitting, registerForm, unregisterForm]);

  const handleDeleteAndProceed = async () => {
    if (isSubmitting) return;
    setIsSubmitting(true);
    // Called after user deletes shifts in other months
    setError(null);

    // OPTIMISTIC: Navigate immediately with shift data encoded in URL
    // The shifts page will handle saving (limit already passed since user deleted other months)
    const optimisticData = encodeURIComponent(JSON.stringify({
      dates: isoDates,
      start,
      end,
      _save: true,
      _checkLimit: false, // Already passed limit check
    }));

    // Clear form state immediately for snappy feel
    setDates([]);
    setStart("");
    setEnd("");
    setError(null);

    // Navigate immediately - shifts page will handle both display AND saving
    navigate(`/${locale}/shifts?optimistic=${optimisticData}`);
  };

  const selectedSummary = useMemo(() => {
    if (dates.length === 0) return t.pages.shifts.add.form.selectDates;
    const sorted = [...dates].sort((a, b) => a.getTime() - b.getTime());
    const first = toLocalISODate(sorted[0]);
    const last = toLocalISODate(sorted[sorted.length - 1]);
    if (sorted.length === 1) return t.pages.shifts.add.form.dateSelected.replace('{date}', first);
    return t.pages.shifts.add.form.datesSelected
      .replace('{count}', sorted.length.toString())
      .replace('{first}', first)
      .replace('{last}', last);
  }, [dates, t]);

  const previewEarnings = useMemo(() => {
    if (!/^\d{2}:\d{2}$/.test(start) || !/^\d{2}:\d{2}$/.test(end) || isoDates.length === 0) {
      return {};
    }

    const result: Record<ISODate, number> = {};
    for (const iso of isoDates) {
      try {
        // Find the applicable wage snapshot for this shift date
        // Snapshots are ordered by from_date DESC (newest first)
        const applicableSnapshot = wageSnapshots.find(
          (snapshot) => snapshot.from_date !== null && snapshot.from_date <= iso
        );

        // Fall back to baseline snapshot (from_date = NULL) if no dated snapshot matches
        const baselineSnapshot = wageSnapshots.find((snapshot) => snapshot.from_date === null);
        const snapshot = applicableSnapshot || baselineSnapshot || null;

        const computed = computeShift(
          {
            id: `preview-${iso}`,
            user_id: "preview",
            shift_date: iso,
            start_time: start,
            end_time: end,
          },
          userSettings,
          presetRules,
          snapshot
        );
        result[iso as ISODate] = computed.gross;
      } catch (err) {
        console.error("Failed to compute preview earnings for shift:", err);
        return {};
      }
    }
    return result;
  }, [start, end, isoDates, userSettings, presetRules, wageSnapshots]);

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
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-6 pt-8 pb-24">
      <div className="flex flex-col gap-4">
        <div className="space-y-1">
          <span className="text-xs font-semibold uppercase tracking-[0.2em] text-brand-highlight">
            {t.pages.shifts.add.subtitle}
          </span>
          <div className="flex items-center justify-between gap-3">
            <h1 className="whitespace-nowrap text-2xl font-semibold text-text-primary sm:text-3xl">
              {t.pages.shifts.add.heading}
            </h1>
            <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 shadow-app-sm dark:shadow-app-inner shrink-0">
              <Button
                type="button"
                variant="ghost"
                aria-pressed={mode === "single"}
                onClick={() => setMode("single")}
                className={cn(
                  "h-9 rounded-full px-4 text-sm transition-all whitespace-nowrap",
                  mode === "single"
                    ? "bg-brand-gradient-mid text-text-inverse shadow-app"
                    : "text-text-secondary hover:text-text-primary"
                )}
              >
                {t.pages.shifts.add.modeSingle}
              </Button>
              <Button
                type="button"
                variant="ghost"
                aria-pressed={mode === "recurring"}
                onClick={() => setMode("recurring")}
                className={cn(
                  "h-9 rounded-full px-4 text-sm transition-all whitespace-nowrap",
                  mode === "recurring"
                    ? "bg-brand-gradient-mid text-text-inverse shadow-app"
                    : "text-text-secondary hover:text-text-primary"
                )}
              >
                {t.pages.shifts.add.modeRecurring}
              </Button>
            </div>
          </div>
        </div>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <p className="text-sm text-text-secondary">
            {mode === "single" ? t.pages.shifts.add.description : t.pages.shifts.add.descriptionRecurring}
          </p>
        </div>

        {/* Offline Mode Banner */}
        {isOffline && (
          <div className="rounded-2xl border border-warning/40 bg-warning-subtle px-4 py-3 shadow-app-inner">
            <p className="text-sm font-medium text-warning">
              📱 <strong>Calculator Mode</strong> - You&apos;re offline. Use this page to preview shift earnings, but you won&apos;t be able to save shifts until you&apos;re back online.
            </p>
          </div>
        )}
      </div>
      <div className="space-y-6">
        {mode === "single" ? (
          <>
            <div className="flex flex-wrap items-center justify-between gap-4">
              <MonthPicker
                month={month}
                onPreviousMonth={goToPreviousMonth}
                onNextMonth={goToNextMonth}
                direction={direction === 'next' ? 'forward' : direction === 'previous' ? 'backward' : undefined}
                isHydrated={isHydrated}
              />
              <span className="rounded-full bg-surface-secondary/80 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-text-muted">
                {month.getFullYear()}
              </span>
            </div>

            <SelectDatesCalendar
                month={month}
                onMonthChange={setMonth}
                selected={dates}
                onSelectedChange={handleSelectedChange}
                hasShiftDates={hasShiftDates}
                conflictDates={conflictDates}
                _hideCaptionNav
                previewEarnings={previewEarnings}
              />

            {showMultiMonthWarning && (
              <div className="rounded-2xl border border-warning/40 bg-warning-subtle px-4 py-3 text-sm text-warning">
                {t.pages.shifts.add.form.multiMonthWarning}
                <Link href="/settings/subscription" className="font-semibold underline underline-offset-4">
                  {t.pages.shifts.add.form.upgrade}
                </Link>
                {t.pages.shifts.add.form.upgradeToAddMore}
              </div>
            )}

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <label htmlFor={startTimeId} className="block min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner transition hover:border-border">
                <span className="text-xs font-semibold uppercase tracking-widest text-text-muted">
                  {t.pages.shifts.add.form.start}
                </span>
                <div className="flex min-w-0 items-center gap-2">
                  <TimeInput
                    id={startTimeId}
                    ref={startInputRef}
                    step={900}
                    value={start}
                    onChange={setStart}
                    onComplete={() => endInputRef.current?.focus()}
                  />
                  <button
                    type="button"
                    onClick={() => openNativePicker(startInputRef.current)}
                    className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-border-subtle bg-surface-secondary/70 text-text-muted transition hover:border-border hover:text-text-primary focus:outline-none focus-visible:outline-none"
                    aria-label={t.pages.shifts.add.form.selectStartTime}
                  >
                    <Clock className="h-5 w-5" strokeWidth={1.5} />
                  </button>
                </div>
              </label>
              <label htmlFor={endTimeId} className="block min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner transition hover:border-border">
                <span className="text-xs font-semibold uppercase tracking-widest text-text-muted">
                  {t.pages.shifts.add.form.end}
                </span>
                <div className="flex min-w-0 items-center gap-2">
                  <TimeInput
                    id={endTimeId}
                    ref={endInputRef}
                    step={900}
                    value={end}
                    onChange={setEnd}
                    onEnter={() => {
                      if (canSubmit) {
                        onSubmit();
                      }
                    }}
                  />
                  <button
                    type="button"
                    onClick={() => openNativePicker(endInputRef.current)}
                    className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-border-subtle bg-surface-secondary/70 text-text-muted transition hover:border-border hover:text-text-primary focus:outline-none focus-visible:outline-none"
                    aria-label={t.pages.shifts.add.form.selectEndTime}
                  >
                    <Clock className="h-5 w-5" strokeWidth={1.5} />
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
                disabled={!canSubmit || isSubmitting}
                loading={isSubmitting}
                className="w-full max-w-md rounded-2xl bg-brand-gradient-mid px-8 py-5 text-lg font-semibold text-text-inverse shadow-app transition hover:bg-brand-gradient-end disabled:opacity-50 disabled:cursor-not-allowed"
                title={isOffline ? "Cannot save shifts while offline" : undefined}
              >
                {isOffline
                  ? "📱 Calculator Mode (Offline)"
                  : dates.length === 1
                    ? t.pages.shifts.add.form.addShifts.replace('{count}', '1')
                    : t.pages.shifts.add.form.addShiftsPlural.replace('{count}', (dates.length || 0).toString())
                }
              </Button>
            </div>
          </>
        ) : (
          <RecurringForm
            existingShifts={existingShifts}
            userSettings={userSettings}
            presetRules={presetRules}
          />
        )}
      </div>

      {/* Free tier limitation modal */}
      {limitModalData && (
        <FreeTierLimitModal
          open={showLimitModal}
          onOpenChange={(open) => {
            setShowLimitModal(open);
            // Clear modal data when closing to prevent reopening
            if (!open) {
              setLimitModalData(null);
            }
          }}
          existingMonths={limitModalData.existingMonths}
          targetMonth={limitModalData.targetMonth}
          onDeleteComplete={handleDeleteAndProceed}
        />
      )}
    </div>
  );
}
