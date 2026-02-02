"use client";

import { useId, useMemo, useRef, useState, useTransition, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import { TimeInput } from "@/components/app/TimeInput";
import { Button } from "@/components/app/Button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/app/Dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/app/Select";
import { RecurringCalendar } from "@/components/app/RecurringCalendar";
import { WeekdayChips } from "@/components/app/WeekdayChips";
import { DurationSection } from "@/components/app/DurationSection";
import { MonthPicker } from "@/components/app/MonthPicker";
import { createRecurringShift } from "@/app/[locale]/(app)/shifts/add/_actions/createRecurringShift";
import { Clock } from "lucide-react";
import { cn } from "@/lib/cn";
import { useMonth } from "@/components/app/MonthContext";
import { useTranslations, useLocale } from "@/lib/i18n/client";
import type { RecurringDraft } from "@/lib/recurring/types";
import type { ExistingShift } from "@/lib/recurring/conflicts";
import type { UserSettings, SupplementRule } from "@/lib/payroll";
import { saveRecurringDraft, loadRecurringDraft, clearRecurringDraft } from "@/lib/recurring/storage";
import { generateVirtualShiftsForMonth, resolveEndWindow } from "@/lib/recurring/utils";
import { detectConflicts, buildConflictDateSet } from "@/lib/recurring/conflicts";

type RecurringFormProps = {
  existingShifts: ExistingShift[];
  userSettings: UserSettings;
  presetRules: SupplementRule[];
};

export default function RecurringForm({ existingShifts, userSettings, presetRules }: RecurringFormProps) {
  const { t } = useTranslations();
  const locale = useLocale();
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const { selectedMonth: month, setSelectedMonth: _setMonth, goToPreviousMonth, goToNextMonth, direction, isHydrated } = useMonth();

  // Initialize draft from localStorage or defaults
  const [draft, setDraft] = useState<RecurringDraft>(() => {
    const saved = loadRecurringDraft();
    if (saved) return saved;

    return {
      start_time: "",
      end_time: "",
      repeat_interval_weeks: 0,
      selected_days: {},
      end_condition: { type: 'months', value: 6 },
      exclusions: [],
    };
  });

  const [error, setError] = useState<string | null>(null);
  const [showPreview, setShowPreview] = useState(false);
  const [_conflicts, _setConflicts] = useState<Map<string, ExistingShift[]>>(new Map());

  const startInputRef = useRef<HTMLInputElement>(null);
  const endInputRef = useRef<HTMLInputElement>(null);
  const startTimeId = useId();
  const endTimeId = useId();

  // Save draft to sessionStorage on every change
  useEffect(() => {
    saveRecurringDraft(draft);
  }, [draft]);

  // Generate all projected dates for preview
  const projectedDates = useMemo(() => {
    if (Object.keys(draft.selected_days).length === 0) return [];

    const dates: string[] = [];
    const startYear = new Date().getUTCFullYear();
    const endYear = startYear + 2; // Max 2 years preview

    for (let year = startYear; year <= endYear; year++) {
      for (let month = 1; month <= 12; month++) {
        const virtualShifts = generateVirtualShiftsForMonth({ year, month }, draft);
        virtualShifts.forEach((vs) => dates.push(vs.date));
      }
    }

    return dates.sort();
  }, [draft]);

  // Detect conflicts for all projected dates (for preview display)
  const previewConflicts = useMemo(() => {
    if (projectedDates.length === 0 || !draft.start_time || !draft.end_time) {
      return new Set<string>();
    }

    const allVirtualShifts = projectedDates.map(date => ({
      date,
      weekday: new Date(date + 'T00:00:00Z').getUTCDay()
    }));

    const conflicts = detectConflicts(
      allVirtualShifts,
      existingShifts,
      draft.start_time,
      draft.end_time
    );

    return buildConflictDateSet(conflicts);
  }, [projectedDates, existingShifts, draft.start_time, draft.end_time]);

  // Calculate date window for month navigation constraints (using local time to match MonthContext)
  const dateWindow = useMemo(() => {
    if (Object.keys(draft.selected_days).length === 0) return null;
    // For infinite recurring, only get the minimum boundary (earliest anchor)
    if (draft.end_condition === null) {
      const anchors = Object.values(draft.selected_days);
      const anchorDates = anchors.map((iso) => new Date(iso + 'T00:00:00Z'));
      const minAnchor = new Date(Math.min(...anchorDates.map((d) => d.getTime())));
      // Use local time to match MonthContext
      return {
        minMonth: new Date(minAnchor.getUTCFullYear(), minAnchor.getUTCMonth(), 1),
        maxMonth: null, // No maximum for infinite recurring
      };
    }
    const window = resolveEndWindow(draft.selected_days, draft.end_condition);
    if (!window) return null;
    // Convert UTC window to local time to match MonthContext
    return {
      minMonth: new Date(window.minMonth.getUTCFullYear(), window.minMonth.getUTCMonth(), 1),
      maxMonth: new Date(window.maxMonth.getUTCFullYear(), window.maxMonth.getUTCMonth(), 1),
    };
  }, [draft]);

  // Check if month navigation should be disabled
  const canNavigateToPreviousMonth = useMemo(() => {
    if (!dateWindow) return true; // Allow navigation if no anchors selected
    const prevMonth = new Date(month.getFullYear(), month.getMonth() - 1, 1);
    return prevMonth >= dateWindow.minMonth;
  }, [month, dateWindow]);

  const canNavigateToNextMonth = useMemo(() => {
    if (!dateWindow) return true; // Allow navigation if no anchors selected
    // For infinite recurring, always allow forward navigation
    if (dateWindow.maxMonth === null) return true;
    const nextMonth = new Date(month.getFullYear(), month.getMonth() + 1, 1);
    return nextMonth <= dateWindow.maxMonth;
  }, [month, dateWindow]);

  const canSubmit =
    Object.keys(draft.selected_days).length > 0 &&
    /^\d{2}:\d{2}$/.test(draft.start_time) &&
    /^\d{2}:\d{2}$/.test(draft.end_time);

  const handlePreview = () => {
    if (!canSubmit) return;
    setError(null);
    setShowPreview(true);
  };

  const handleConfirm = async () => {
    setError(null);
    // Close modal immediately
    setShowPreview(false);

    startTransition(async () => {
      try {
        const result = await createRecurringShift(draft);
        // Clear sessionStorage immediately
        clearRecurringDraft();
        // Reset draft state to prevent useEffect from re-saving
        setDraft({
          start_time: "",
          end_time: "",
          repeat_interval_weeks: 0,
          selected_days: {},
          end_condition: { type: 'months', value: 6 },
          exclusions: [],
        });
        // Navigate with recurring ID to trigger celebration
        router.push(`/${locale}/shifts?newRecurring=${result.id}`);
      } catch (e: any) {
        setError(e?.message || t.pages.shifts.add.form.couldNotSaveShift);
        // Reopen modal on error to show the error message
        setShowPreview(true);
      }
    });
  };

  const recurringSummary = useMemo(() => {
    const anchorCount = Object.keys(draft.selected_days).length;
    if (anchorCount === 0) {
      return t.pages.shifts.add.recurring.selectUpTo7Weekdays;
    }

    const hasTimes = /^\d{2}:\d{2}$/.test(draft.start_time) && /^\d{2}:\d{2}$/.test(draft.end_time);
    const timeRange = hasTimes ? `${draft.start_time}–${draft.end_time}` : t.pages.shifts.add.recurring.specifyTime;

    // Handle infinite recurring (no end condition)
    if (draft.end_condition === null) {
      if (projectedDates.length === 0) {
        return t.pages.shifts.add.recurring.noShiftsGenerated;
      }
      const first = projectedDates[0];
      return t.pages.shifts.add.recurring.infiniteRecurring
        .replace('{first}', first)
        .replace('{time}', timeRange);
    }

    const projCount = projectedDates.length;

    if (projCount === 0) {
      return t.pages.shifts.add.recurring.noShiftsGenerated;
    }

    const first = projectedDates[0];
    const last = projectedDates[projectedDates.length - 1];

    if (projCount === 1) {
      return t.pages.shifts.add.recurring.recurringWith1Shift
        .replace('{time}', timeRange)
        .replace('{date}', first);
    }

    return t.pages.shifts.add.recurring.recurringWithShifts
      .replace('{count}', projCount.toString())
      .replace('{first}', first)
      .replace('{last}', last)
      .replace('{time}', timeRange);
  }, [draft, projectedDates, t]);

  const fieldWrapperClass = "block min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner transition hover:border-border";
  const fieldLabelClass = "text-xs font-semibold uppercase tracking-widest text-text-muted";

  const openNativePicker = (input: HTMLInputElement | null) => {
    if (!input) return;
    const picker = (input as unknown as { showPicker?: () => void }).showPicker;
    if (typeof picker === "function") {
      picker.call(input);
    } else {
      input.focus();
    }
  };

  const handleRemoveWeekday = useCallback((weekday: '0' | '1' | '2' | '3' | '4' | '5' | '6') => {
    const newSelected = { ...draft.selected_days };
    delete newSelected[weekday];
    setDraft({ ...draft, selected_days: newSelected });
  }, [draft]);

  const handleCalendarError = useCallback((errorMsg: string) => {
    setError(errorMsg);
  }, []);

  return (
    <div className="space-y-6">
      {/* Time inputs */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label htmlFor={startTimeId} className={fieldWrapperClass}>
          <span className={fieldLabelClass}>{t.pages.shifts.add.form.start}</span>
          <div className="flex min-w-0 items-center gap-2">
            <TimeInput
              id={startTimeId}
              ref={startInputRef}
              value={draft.start_time}
              onChange={(val) => setDraft({ ...draft, start_time: val })}
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
        <label htmlFor={endTimeId} className={fieldWrapperClass}>
          <span className={fieldLabelClass}>{t.pages.shifts.add.form.end}</span>
          <div className="flex min-w-0 items-center gap-2">
            <TimeInput
              id={endTimeId}
              ref={endInputRef}
              value={draft.end_time}
              onChange={(val) => setDraft({ ...draft, end_time: val })}
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

      <div className="h-px bg-border-subtle" />

      {/* Repeat interval */}
      <div className="flex items-center justify-center gap-2 py-1">
        <span className="text-base text-text-primary">{t.pages.shifts.add.recurring.repeatEvery}</span>
        <Select
          value={String(draft.repeat_interval_weeks)}
          onValueChange={(value) => {
            const num = parseInt(value, 10);
            setDraft({ ...draft, repeat_interval_weeks: num as any });
          }}
        >
          <SelectTrigger className="h-10 w-auto min-w-25 rounded-xl border-border-subtle bg-surface-secondary/70 text-base text-text-primary">
            <SelectValue />
          </SelectTrigger>
          <SelectContent className="rounded-xl border-border-subtle bg-surface-primary shadow-app-lg">
            {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((num) => (
              <SelectItem
                key={num}
                value={String(num)}
                className="cursor-pointer rounded-lg text-text-primary hover:bg-surface-secondary focus:bg-surface-secondary"
              >
                {t.pages.shifts.add.recurring.weekOrdinals[(num + 1) as keyof typeof t.pages.shifts.add.recurring.weekOrdinals]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <span className="text-base text-text-primary">{t.pages.shifts.add.recurring.week}</span>
      </div>

      <div className="h-px bg-border-subtle" />

      {/* Duration section */}
      <DurationSection
        value={draft.end_condition}
        onChange={(val) => setDraft({ ...draft, end_condition: val })}
      />

      <div className="h-px bg-border-subtle" />

      {/* Calendar instructions */}
      <div className="space-y-2 pt-2">
        <h3 className="text-xs font-semibold uppercase tracking-widest text-text-muted">
          {t.pages.shifts.add.recurring.calendarInstructionsHeader}
        </h3>
        <p className="text-sm text-text-secondary leading-relaxed">
          {t.pages.shifts.add.recurring.calendarInstructionsSubheader}
        </p>
      </div>

      {/* Month picker */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <MonthPicker
          month={month}
          onPreviousMonth={goToPreviousMonth}
          onNextMonth={goToNextMonth}
          canNavigateToPreviousMonth={canNavigateToPreviousMonth}
          canNavigateToNextMonth={canNavigateToNextMonth}
          direction={direction === 'next' ? 'forward' : direction === 'previous' ? 'backward' : undefined}
          isHydrated={isHydrated}
        />
        <span className="rounded-full bg-surface-secondary/80 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-text-muted">
          {month.getFullYear()}
        </span>
      </div>

      {/* Weekday chips */}
      <WeekdayChips
        selected={draft.selected_days}
        onRemove={handleRemoveWeekday}
      />

      {/* Recurring calendar */}
      <RecurringCalendar
        value={draft}
        onChange={setDraft}
        existingShifts={existingShifts}
        userSettings={userSettings}
        presetRules={presetRules}
        onConflictsFound={_setConflicts}
        onError={handleCalendarError}
      />

      {/* Summary - only show when dates are selected */}
      {Object.keys(draft.selected_days).length > 0 && (
        <div className="rounded-2xl border border-border-subtle bg-surface-secondary/70 px-4 py-3 text-sm text-text-secondary shadow-app-inner">
          {recurringSummary}
        </div>
      )}

      {/* Warning display */}
      {error && (
        <div
          className="rounded-2xl border border-warning/30 bg-warning-subtle px-4 py-3 text-sm font-medium text-warning shadow-app-inner"
          role="alert"
        >
          {error}
        </div>
      )}

      {/* Submit button */}
      <div className="flex justify-center">
        <Button
          onClick={handlePreview}
          disabled={!canSubmit}
          loading={pending}
          className="rounded-2xl bg-brand-gradient-mid px-6 py-3 text-base font-semibold text-text-inverse shadow-app transition hover:bg-brand-gradient-end"
        >
          {draft.end_condition === null
            ? t.pages.shifts.add.recurring.previewInfiniteRecurring
            : t.pages.shifts.add.recurring.previewRecurring.replace('{count}', projectedDates.length.toString())}
        </Button>
      </div>

      {/* Preview modal */}
      <Dialog open={showPreview} onOpenChange={setShowPreview}>
        <DialogContent className="max-w-md border border-border-subtle bg-surface-primary/95 shadow-app-lg">
          <DialogHeader>
            <DialogTitle>{t.pages.shifts.add.recurring.confirmRecurring}</DialogTitle>
            <DialogDescription className="space-y-2">
              {draft.end_condition === null
                ? t.pages.shifts.add.recurring.confirmingInfiniteRecurringDescription
                : t.pages.shifts.add.recurring.confirmingRecurringDescription.replace('{count}', projectedDates.length.toString())}
              {previewConflicts.size > 0 && (
                <>
                  <br />
                  <span className="text-warning">
                    {(previewConflicts.size === 1
                      ? t.pages.shifts.add.recurring.conflictsWarningSingular
                      : t.pages.shifts.add.recurring.conflictsWarning
                    ).replace('{count}', previewConflicts.size.toString())}
                  </span>
                </>
              )}
            </DialogDescription>
          </DialogHeader>
          <div className="max-h-56 space-y-2 overflow-auto rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 text-sm text-text-primary shadow-app-inner">
            {projectedDates.slice(0, 20).map((d) => {
              const isConflict = previewConflicts.has(d);
              return (
                <div
                  key={d}
                  className={cn(
                    "flex items-center justify-between gap-2 rounded-xl px-3 py-2",
                    isConflict
                      ? "bg-warning-subtle/50 border border-warning/30"
                      : "bg-surface-primary/70"
                  )}
                >
                  <span className={cn("font-medium", isConflict && "line-through opacity-60")}>
                    {d}
                  </span>
                  <span className={cn("text-sm", isConflict ? "text-warning line-through opacity-60" : "text-text-secondary")}>
                    {draft.start_time}–{draft.end_time}
                  </span>
                </div>
              );
            })}
            {projectedDates.length > 20 && (
              <div className="rounded-xl bg-surface-primary/60 px-3 py-2 text-center text-sm text-text-muted shadow-app-inner">
                {t.pages.shifts.add.recurring.andMore.replace('{count}', (projectedDates.length - 20).toString())}
              </div>
            )}
          </div>
          <DialogFooter className="gap-2 pt-4">
            <Button
              type="button"
              variant="ghost"
              onClick={() => setShowPreview(false)}
              className="rounded-xl px-4 py-2 text-text-secondary hover:text-text-primary"
            >
              {t.pages.shifts.add.recurring.cancel}
            </Button>
            <Button
              type="button"
              onClick={handleConfirm}
              loading={pending}
              className="rounded-xl bg-brand-gradient-mid px-5 py-2 font-semibold text-text-inverse shadow-app transition hover:bg-brand-gradient-end"
            >
              {t.pages.shifts.add.recurring.confirm}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
