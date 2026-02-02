"use client";

import { useMemo, useCallback, useEffect } from "react";
import { SelectDatesCalendar } from "./SelectDatesCalendar";
import { toISODate } from "./calendar-utils";
import type { ISODate } from "./calendar-utils";
import type { RecurringDraft, RecurringVirtualShift } from "@/lib/recurring/types";
import type { ExistingShift } from "@/lib/recurring/conflicts";
import type { UserSettings, SupplementRule } from "@/lib/payroll";
import {
  generateVirtualShiftsForMonth,
  formatWeekdayName,
} from "@/lib/recurring/utils";
import { detectConflicts, buildConflictDateSet } from "@/lib/recurring/conflicts";
import { computeShift } from "@/lib/payroll";
import { useLocale, useTranslations } from "@/lib/i18n/client";
import { useMonth } from "@/components/app/MonthContext";

/**
 * Get weekday key (0-6) from a Date object using local time
 * 0 = Sunday, 1 = Monday, ..., 6 = Saturday
 */
function getWeekdayKey(date: Date): '0' | '1' | '2' | '3' | '4' | '5' | '6' {
  return String(date.getDay()) as '0' | '1' | '2' | '3' | '4' | '5' | '6';
}

export type RecurringCalendarProps = {
  /** Current recurring draft */
  value: RecurringDraft;
  /** Callback when draft changes */
  onChange: (draft: RecurringDraft) => void;
  /** Existing shifts for conflict detection */
  existingShifts: ExistingShift[];
  /** User settings for earnings preview */
  userSettings: UserSettings;
  /** Preset supplement rules for earnings preview */
  presetRules: SupplementRule[];
  /** Callback when conflicts are detected */
  onConflictsFound?: (conflicts: Map<string, ExistingShift[]>) => void;
  /** Callback when user attempts invalid selection */
  onError?: (error: string) => void;
  /** Optional className */
  className?: string;
};

/**
 * RecurringCalendar component
 *
 * Calendar interface for building recurring shift patterns.
 * Users select up to 7 anchor dates (one per weekday).
 * The calendar shows virtual shifts (projected occurrences) and detects conflicts.
 */
export function RecurringCalendar({
  value,
  onChange,
  existingShifts,
  userSettings,
  presetRules,
  onConflictsFound,
  onError,
  className,
}: RecurringCalendarProps) {
  const locale = useLocale();
  const { t } = useTranslations();
  const { selectedMonth: month, setSelectedMonth: setMonth } = useMonth();

  // Generate virtual shifts for the current month
  const virtualShifts = useMemo<RecurringVirtualShift[]>(() => {
    if (Object.keys(value.selected_days).length === 0) return [];

    const yearMonth = {
      year: month.getFullYear(),
      month: month.getMonth() + 1,
    };

    return generateVirtualShiftsForMonth(yearMonth, value);
  }, [month, value]);

  // Compute earnings for virtual shifts AND anchors
  const virtualShiftEarnings = useMemo<Partial<Record<ISODate, number>>>(() => {
    if (!/^\d{2}:\d{2}$/.test(value.start_time) || !/^\d{2}:\d{2}$/.test(value.end_time)) {
      return {};
    }

    const result: Partial<Record<ISODate, number>> = {};

    // Compute for all virtual shifts
    for (const virtualShift of virtualShifts) {
      try {
        const computed = computeShift(
          {
            id: `virtual-${virtualShift.date}`,
            user_id: 'preview',
            shift_date: virtualShift.date,
            start_time: value.start_time,
            end_time: value.end_time,
          },
          userSettings,
          presetRules
        );
        result[virtualShift.date as ISODate] = computed.gross;
      } catch (err) {
        console.error(`Failed to compute earnings for virtual shift ${virtualShift.date}:`, err);
      }
    }

    // Also compute for anchor dates
    for (const anchorDate of Object.values(value.selected_days)) {
      try {
        const computed = computeShift(
          {
            id: `anchor-${anchorDate}`,
            user_id: 'preview',
            shift_date: anchorDate,
            start_time: value.start_time,
            end_time: value.end_time,
          },
          userSettings,
          presetRules
        );
        result[anchorDate as ISODate] = computed.gross;
      } catch (err) {
        console.error(`Failed to compute earnings for anchor ${anchorDate}:`, err);
      }
    }

    return result;
  }, [virtualShifts, value.start_time, value.end_time, value.selected_days, userSettings, presetRules]);

  // Detect conflicts
  const conflicts = useMemo(() => {
    if (virtualShifts.length === 0) return new Map<string, ExistingShift[]>();
    return detectConflicts(virtualShifts, existingShifts, value.start_time, value.end_time);
  }, [virtualShifts, existingShifts, value.start_time, value.end_time]);

  const conflictDates = useMemo(() => buildConflictDateSet(conflicts) as Set<ISODate>, [conflicts]);

  // Notify parent of conflicts
  useEffect(() => {
    if (onConflictsFound) {
      onConflictsFound(conflicts);
    }
  }, [conflicts, onConflictsFound]);

  // Convert anchors to Date[] for SelectDatesCalendar
  const selectedDates = useMemo<Date[]>(() => {
    return Object.values(value.selected_days).map((iso) => new Date(iso + 'T00:00:00Z'));
  }, [value.selected_days]);

  // Has shift dates = anchors + virtual shifts
  const hasShiftDates = useMemo<Set<ISODate>>(() => {
    const set = new Set<ISODate>();
    Object.values(value.selected_days).forEach((iso) => set.add(iso as ISODate));
    virtualShifts.forEach((vs) => set.add(vs.date as ISODate));
    return set;
  }, [value.selected_days, virtualShifts]);

  // Handle date selection
  const handleDateSelect = useCallback(
    (dates: Date[]) => {
      if (dates.length === 0) {
        // Clearing all - allow
        onChange({ ...value, selected_days: {} });
        return;
      }

      // User clicked on a date
      // Find the newly clicked date
      const newDate = dates.find((d) => {
        const iso = toISODate(d);
        return !Object.values(value.selected_days).includes(iso);
      });

      if (!newDate) {
        // User removed a date
        const removed = Object.values(value.selected_days).find((iso) => {
          return !dates.some((d) => toISODate(d) === iso);
        });
        if (removed) {
          const newSelected = { ...value.selected_days };
          const weekdayKey = Object.keys(newSelected).find(
            (k) => newSelected[k as keyof typeof newSelected] === removed
          ) as '0' | '1' | '2' | '3' | '4' | '5' | '6' | undefined;
          if (weekdayKey) {
            delete newSelected[weekdayKey];
            onChange({ ...value, selected_days: newSelected });
          }
        }
        return;
      }

      const newISO = toISODate(newDate);
      const weekdayKey = getWeekdayKey(newDate);

      // Check if this weekday is already selected
      const existingAnchor = value.selected_days[weekdayKey];

      if (existingAnchor && existingAnchor !== newISO) {
        // User is trying to select a different date for the same weekday - show warning
        const weekdayName = formatWeekdayName(weekdayKey, locale);
        if (onError) {
          onError(t.pages.shifts.add.recurring.errors.duplicateWeekday.replace('{weekday}', weekdayName));
        }
        return;
      }

      // Check if we already have 7 weekdays
      const selectedCount = Object.keys(value.selected_days).length;
      if (selectedCount >= 7 && !existingAnchor) {
        if (onError) {
          onError(t.pages.shifts.add.recurring.errors.maxWeekdays);
        }
        return;
      }

      // Check if this date has conflicts
      if (conflictDates.has(newISO as ISODate)) {
        if (onError) {
          onError(t.pages.shifts.add.recurring.errors.hasConflict);
        }
        return;
      }

      // Add or update anchor
      const newSelected = { ...value.selected_days, [weekdayKey]: newISO };
      onChange({ ...value, selected_days: newSelected });
    },
    [value, onChange, conflictDates, locale, t, onError]
  );

  // Handle month navigation
  const handleMonthChange = useCallback((newMonth: Date) => {
    setMonth(newMonth);
  }, [setMonth]);

  return (
    <div className={className}>
      <SelectDatesCalendar
        month={month}
        onMonthChange={handleMonthChange}
        selected={selectedDates}
        onSelectedChange={handleDateSelect}
        hasShiftDates={hasShiftDates}
        conflictDates={conflictDates}
        previewEarnings={virtualShiftEarnings}
        _hideCaptionNav={false}
        disabledOutsideMonth={true}
      />
      <div className="mt-4 text-center text-sm text-text-muted">
        {t.pages.shifts.add.recurring.selectUpTo7Weekdays}
      </div>
    </div>
  );
}
