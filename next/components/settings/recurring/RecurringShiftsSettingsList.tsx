"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { CalendarClock, ChevronRight } from "lucide-react";
import { Card } from "@/components/app/Card";
import { RecurringEditModal } from "@/components/shifts/RecurringEditModal";
import { useLocale, useTranslations } from "@/lib/i18n/client";
import { cleanTime } from "@/lib/date-utils";
import { formatWeekdayShort } from "@/lib/recurring/utils";
import type { ExistingShift } from "@/lib/recurring/conflicts";
import type { RecurringShiftRow } from "@/lib/recurring/types";
import type { SupplementRule, UserSettings } from "@/lib/payroll";

type RecurringShiftsSettingsListProps = {
  recurringShifts: RecurringShiftRow[];
  existingShifts: ExistingShift[];
  userSettings: UserSettings;
  presetRules: SupplementRule[];
  cacheKey?: string;
};

export function RecurringShiftsSettingsList({
  recurringShifts,
  existingShifts,
  userSettings,
  presetRules,
  cacheKey,
}: RecurringShiftsSettingsListProps) {
  const { t } = useTranslations();
  const locale = useLocale();
  const router = useRouter();
  const [editingRecurringId, setEditingRecurringId] = useState<string | null>(null);

  const sortedRecurring = useMemo(() => {
    return [...recurringShifts].sort((a, b) => {
      const earliestA = Object.values(a.selected_days ?? {}).sort()[0] ?? "9999-12-31";
      const earliestB = Object.values(b.selected_days ?? {}).sort()[0] ?? "9999-12-31";
      if (earliestA !== earliestB) return earliestA.localeCompare(earliestB);

      const startA = cleanTime(a.start_time);
      const startB = cleanTime(b.start_time);
      if (startA !== startB) return startA.localeCompare(startB);

      return a.id.localeCompare(b.id);
    });
  }, [recurringShifts]);

  const formatDate = (isoDate: string) => {
    const date = new Date(`${isoDate}T00:00:00`);
    if (Number.isNaN(date.getTime())) return isoDate;
    return new Intl.DateTimeFormat(locale === "no" ? "nb-NO" : "en-US", {
      weekday: "short",
      year: "numeric",
      month: "short",
      day: "numeric",
    }).format(date);
  };

  const formatWeekdays = (selectedDays: RecurringShiftRow["selected_days"]) => {
    const order: Array<"0" | "1" | "2" | "3" | "4" | "5" | "6"> = ["1", "2", "3", "4", "5", "6", "0"];
    const labels = order
      .filter((weekday) => Boolean(selectedDays?.[weekday]))
      .map((weekday) => formatWeekdayShort(weekday, locale));

    return labels.join(", ");
  };

  const repeatLabel = (repeatIntervalWeeks: number) => {
    if (repeatIntervalWeeks === 0) {
      return t.pages.shifts.add.recurring.everyWeek;
    }

    return t.pages.shifts.add.recurring.everyNWeeks.replace("{n}", String(repeatIntervalWeeks + 1));
  };

  if (sortedRecurring.length === 0) {
    return (
      <Card className="p-5">
        <h3 className="text-base font-semibold text-text-primary">
          {t.pages.settings.recurring.emptyTitle}
        </h3>
        <p className="mt-1 text-sm text-text-secondary">
          {t.pages.settings.recurring.emptyDescription}
        </p>
      </Card>
    );
  }

  return (
    <>
      <div className="space-y-3">
        {sortedRecurring.map((recurring) => {
          const cleanedStart = cleanTime(recurring.start_time);
          const cleanedEnd = cleanTime(recurring.end_time);
          const exclusions = recurring.exclusions || [];
          const exclusionsLabel = exclusions.length > 0
            ? t.pages.settings.recurring.excludedDates.replace("{count}", String(exclusions.length))
            : null;
          const earliestAnchor = Object.values(recurring.selected_days ?? {}).sort()[0] ?? null;

          return (
            <button
              key={recurring.id}
              type="button"
              onClick={() => setEditingRecurringId(recurring.id)}
              className="w-full text-left"
            >
              <Card className="p-4 transition-colors hover:bg-surface-secondary/50">
                <div className="flex items-start gap-3">
                  <div className="mt-0.5 rounded-lg bg-surface-secondary p-2">
                    <CalendarClock className="h-4 w-4 text-text-primary" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="text-base font-semibold text-text-primary">
                      {cleanedStart}–{cleanedEnd}
                    </p>
                    <p className="mt-0.5 text-sm text-text-secondary">
                      {formatWeekdays(recurring.selected_days)}
                    </p>
                    <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-text-muted">
                      <span>{repeatLabel(recurring.repeat_interval_weeks)}</span>
                      {earliestAnchor && (
                        <span>{formatDate(earliestAnchor)}</span>
                      )}
                      {exclusionsLabel && (
                        <span>{exclusionsLabel}</span>
                      )}
                    </div>
                  </div>
                  <ChevronRight className="mt-0.5 h-4 w-4 shrink-0 text-text-muted" />
                </div>
              </Card>
            </button>
          );
        })}
      </div>

      {editingRecurringId && (
        <RecurringEditModal
          isOpen
          recurringId={editingRecurringId}
          existingShifts={existingShifts}
          userSettings={userSettings}
          presetRules={presetRules}
          cacheKey={cacheKey}
          onClose={() => {
            setEditingRecurringId(null);
            router.refresh();
          }}
        />
      )}
    </>
  );
}
