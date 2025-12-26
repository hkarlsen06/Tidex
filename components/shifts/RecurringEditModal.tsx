"use client";

import { useId, useRef, useState, useTransition, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import { TimeInput } from "@/components/app/TimeInput";
import { Button } from "@/components/app/Button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/app/Dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/app/Select";
import { RecurringCalendar } from "@/components/app/RecurringCalendar";
import { WeekdayChips } from "@/components/app/WeekdayChips";
import { DurationSection } from "@/components/app/DurationSection";
import { MonthPicker } from "@/components/app/MonthPicker";
import { updateRecurringShift } from "@/app/[locale]/(app)/shifts/_actions/updateRecurringShift";
import { deleteRecurringShift } from "@/app/[locale]/(app)/shifts/_actions/deleteRecurringShift";
import { Clock, Trash2 } from "lucide-react";
import { cn } from "@/lib/cn";
import { useMonth } from "@/components/app/MonthContext";
import { useTranslations, useLocale } from "@/lib/i18n/client";
import type { RecurringDraft, RecurringShiftRow } from "@/lib/recurring/types";
import type { ExistingShift } from "@/lib/recurring/conflicts";
import type { UserSettings, SupplementRule } from "@/lib/payroll";

type RecurringEditModalProps = {
  isOpen: boolean;
  recurringId: string;
  onClose: (reason?: 'deleted' | 'cancelled' | 'saved') => void;
  existingShifts: ExistingShift[];
  userSettings: UserSettings;
  presetRules: SupplementRule[];
};

export function RecurringEditModal({
  isOpen,
  recurringId,
  onClose,
  existingShifts,
  userSettings,
  presetRules,
}: RecurringEditModalProps) {
  const { t } = useTranslations();
  const _locale = useLocale();
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [deleting, startDeleteTransition] = useTransition();
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const { selectedMonth: month, setSelectedMonth: setMonth, isHydrated } = useMonth();

  // Load recurring shift data from database
  const [draft, setDraft] = useState<RecurringDraft | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [_conflicts, _setConflicts] = useState<Map<string, ExistingShift[]>>(new Map());

  const startInputRef = useRef<HTMLInputElement>(null);
  const endInputRef = useRef<HTMLInputElement>(null);
  const startTimeId = useId();
  const endTimeId = useId();

  // Load recurring shift data when modal opens
  useEffect(() => {
    if (!isOpen || !recurringId) {
      return;
    }

    async function loadRecurringData() {
      try {
        setLoading(true);
        const response = await fetch(`/api/recurring/${recurringId}`);
        if (!response.ok) {
          throw new Error("Failed to load recurring shift");
        }

        const recurring: RecurringShiftRow = await response.json();

        // Strip timezone and seconds from time strings
        // Input formats: "12:30:00+01:00", "12:30+01:00", "12:30:00", "12:30"
        // Output format: "12:30"
        const cleanTime = (time: string) => {
          // First, remove timezone offset (e.g., "+01:00" or "-05:00")
          // Split on + or - but keep the first part only
          let cleaned = time;
          const plusIndex = cleaned.indexOf('+');
          const minusIndex = cleaned.lastIndexOf('-'); // lastIndexOf to avoid catching negative in time

          if (plusIndex > 0) {
            cleaned = cleaned.substring(0, plusIndex);
          } else if (minusIndex > 2) { // Must be beyond position 2 to be timezone, not part of time
            cleaned = cleaned.substring(0, minusIndex);
          }

          // Now extract just HH:MM (first 5 characters)
          return cleaned.substring(0, 5);
        };

        setDraft({
          start_time: cleanTime(recurring.start_time),
          end_time: cleanTime(recurring.end_time),
          repeat_interval_weeks: recurring.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8,
          selected_days: recurring.selected_days,
          end_condition: recurring.end_condition,
          exclusions: recurring.exclusions || [],
        });
      } catch (err) {
        console.error("Failed to load recurring shift:", err);
        setError(t.pages.shifts.details.errorUpdate);
      } finally {
        setLoading(false);
      }
    }

    loadRecurringData();
  }, [isOpen, recurringId, t]);

  // Clear error on draft change
  useEffect(() => {
    setError(null);
  }, [draft]);

  const handleConflictsFound = useCallback((foundConflicts: Map<string, ExistingShift[]>) => {
    _setConflicts(foundConflicts);
  }, []);

  const handleError = useCallback((message: string) => {
    setError(message);
  }, []);

  const handleSave = useCallback(() => {
    if (!draft) return;

    if (!draft.start_time || !draft.end_time) {
      setError(t.pages.shifts.details.errorInvalidTime);
      return;
    }

    if (Object.keys(draft.selected_days).length === 0) {
      setError(t.pages.shifts.recurringEdit.errorMinimumOneWeekday);
      return;
    }

    startTransition(async () => {
      try {
        await updateRecurringShift({
          id: recurringId,
          start_time: draft.start_time,
          end_time: draft.end_time,
          repeat_interval_weeks: draft.repeat_interval_weeks,
          selected_days: draft.selected_days,
          end_condition: draft.end_condition,
          exclusions: draft.exclusions,
        });

        router.refresh();
        onClose('saved');
      } catch (err: any) {
        setError(err?.message || t.pages.shifts.details.errorUpdate);
      }
    });
  }, [draft, recurringId, router, onClose, t]);

  const handleDelete = useCallback(() => {
    if (!confirmingDelete) {
      setConfirmingDelete(true);
      return;
    }

    startDeleteTransition(async () => {
      try {
        await deleteRecurringShift(recurringId);
        router.refresh();
        onClose('deleted');
      } catch (err: any) {
        setError(err?.message || t.pages.shifts.details.errorUpdate);
        setConfirmingDelete(false);
      }
    });
  }, [confirmingDelete, recurringId, router, onClose, t]);

  const canSave = draft && draft.start_time && draft.end_time && Object.keys(draft.selected_days).length > 0;

  if (!draft || loading) {
    return (
      <Dialog open={isOpen} onOpenChange={(open) => { if (!open && !pending) onClose(); }}>
        <DialogContent className="sm:rounded-3xl max-w-[480px] max-h-[90vh] overflow-y-auto overflow-x-hidden">
          <DialogTitle className="sr-only">{t.pages.shifts.recurringEdit.title}</DialogTitle>
          <div className="flex items-center justify-center py-8">
            <div className="h-8 w-8 animate-spin rounded-full border-4 border-border-subtle border-t-brand-highlight" />
          </div>
        </DialogContent>
      </Dialog>
    );
  }

  return (
    <Dialog open={isOpen} onOpenChange={(open) => { if (!open && !pending) onClose(); }}>
      <DialogContent className="sm:rounded-3xl max-w-[480px] max-h-[90vh] overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-text-primary">
            <Clock className="h-5 w-5 text-text-muted" aria-hidden />
            {t.pages.shifts.recurringEdit.title}
          </DialogTitle>
          <DialogDescription className="text-text-muted">
            {t.pages.shifts.recurringEdit.description}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6 pt-2 min-w-0">
          {/* Time inputs */}
          <div className="flex flex-col gap-4 sm:flex-row sm:items-end min-w-0">
            <div className="flex-1 min-w-0">
              <label htmlFor={startTimeId} className="mb-2 block text-sm font-medium text-text-primary">
                {t.pages.shifts.recurringEdit.startTimeLabel}
              </label>
              <TimeInput
                ref={startInputRef}
                id={startTimeId}
                value={draft.start_time}
                onChange={(value) => setDraft({ ...draft, start_time: value })}
                onComplete={() => endInputRef.current?.focus()}
                disabled={pending}
              />
            </div>
            <div className="flex-1 min-w-0">
              <label htmlFor={endTimeId} className="mb-2 block text-sm font-medium text-text-primary">
                {t.pages.shifts.recurringEdit.endTimeLabel}
              </label>
              <TimeInput
                ref={endInputRef}
                id={endTimeId}
                value={draft.end_time}
                onChange={(value) => setDraft({ ...draft, end_time: value })}
                disabled={pending}
              />
            </div>
          </div>

          <div className="h-px bg-border-subtle" />

          {/* Repeat interval */}
          <div>
            <label className="mb-2 block text-sm font-medium text-text-primary">
              {t.pages.shifts.recurringEdit.repeatIntervalLabel}
            </label>
            <Select
              value={String(draft.repeat_interval_weeks)}
              onValueChange={(value) => setDraft({ ...draft, repeat_interval_weeks: Number(value) as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 })}
              disabled={pending}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((interval) => (
                  <SelectItem key={interval} value={String(interval)}>
                    {interval === 0 ? t.pages.shifts.add.recurring.everyWeek : t.pages.shifts.add.recurring.everyNWeeks.replace('{n}', String(interval + 1))}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="h-px bg-border-subtle" />

          {/* Duration section */}
          <DurationSection
            value={draft.end_condition}
            onChange={(value) => setDraft({ ...draft, end_condition: value })}
          />

          <div className="h-px bg-border-subtle" />

          {/* Calendar instructions */}
          <span className="text-xs font-semibold uppercase tracking-widest text-text-muted">
            {t.pages.shifts.add.recurring.calendarInstructionsHeader}
          </span>

          {/* Month picker */}
          <div className="flex items-center justify-between">
            <MonthPicker
              month={month}
              onPreviousMonth={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))}
              onNextMonth={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))}
              isHydrated={isHydrated}
            />
            <span className="rounded-full bg-surface-secondary/80 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-text-muted">
              {month.getFullYear()}
            </span>
          </div>

          {/* Weekday chips */}
          <WeekdayChips
            selected={draft.selected_days}
            onRemove={(weekdayKey) => {
              const newSelected = { ...draft.selected_days };
              delete newSelected[weekdayKey];
              setDraft({ ...draft, selected_days: newSelected });
            }}
          />

          {/* Calendar */}
          <RecurringCalendar
            value={draft}
            onChange={setDraft}
            existingShifts={existingShifts}
            userSettings={userSettings}
            presetRules={presetRules}
            onConflictsFound={handleConflictsFound}
            onError={handleError}
          />

          {error && (
            <div className="text-sm text-error">{error}</div>
          )}
        </div>

        <DialogFooter className="mt-6 flex flex-col gap-3 sm:flex-row">
          <Button
            onClick={handleDelete}
            disabled={pending || deleting}
            loading={deleting}
            className={cn(
              "flex-1 h-11 rounded-full px-4 text-sm font-medium transition-colors gap-2",
              "bg-rose-600 text-white hover:bg-rose-700"
            )}
          >
            <Trash2 className="h-4 w-4" />
            {confirmingDelete ? t.pages.shifts.recurringEdit.confirmDeleteRecurringButton : t.pages.shifts.recurringEdit.deleteRecurringButton}
          </Button>
          <Button
            onClick={() => {
              setConfirmingDelete(false);
              onClose('cancelled');
            }}
            disabled={pending || deleting}
            variant="ghost"
            className="flex-1 h-11 rounded-full border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900"
          >
            {t.pages.shifts.recurringEdit.cancelButton}
          </Button>
          <Button
            onClick={handleSave}
            disabled={pending || deleting || !canSave}
            loading={pending}
            className="flex-1 h-11 rounded-full"
          >
            {t.pages.shifts.recurringEdit.saveButton}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
