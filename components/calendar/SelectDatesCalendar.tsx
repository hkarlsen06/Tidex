"use client";

import * as React from "react";
import { DayPicker } from "react-day-picker";
import { nb, enUS } from "date-fns/locale";
import { toISODate, type ISODate, formatNOKInt } from "./calendar.utils";
import { cn } from "@/lib/utils";
import { useLocale } from "@/lib/i18n/client";

export type SelectDatesCalendarProps = {
  month: Date; // controlled
  selected: Date[]; // controlled multi-select
  onSelectedChange: (dates: Date[]) => void;
  conflictDates?: Set<ISODate>; // paint yellow
  hasShiftDates?: Set<ISODate>; // highlight date number
  disabledOutsideMonth?: boolean; // default: true
  onMonthChange?: (month: Date) => void;
  _hideCaptionNav?: boolean; // hides built-in caption and nav (reserved for future use)
  previewEarnings?: Partial<Record<ISODate, number>>;
};

export function SelectDatesCalendar({
  month,
  selected,
  onSelectedChange,
  conflictDates = new Set(),
  hasShiftDates = new Set(),
  disabledOutsideMonth = true,
  onMonthChange,
  _hideCaptionNav = false,
  previewEarnings = {},
}: SelectDatesCalendarProps) {
  const locale = useLocale();
  const dateFnsLocale = locale === 'en' ? enUS : nb;

  // Custom formatter for weekday names to show 2-letter abbreviations
  const formatWeekdayName = React.useCallback((date: Date) => {
    const day = date.getDay();
    const shortNames = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
    const shortNamesNb = ['SØ', 'MA', 'TI', 'ON', 'TO', 'FR', 'LØ'];
    const names = locale === 'no' ? shortNamesNb : shortNames;
    return names[day];
  }, [locale]);

  function getIsoWeek(date: Date) {
    const d = new Date(
      Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())
    );
    const day = d.getUTCDay() || 7;
    d.setUTCDate(d.getUTCDate() + 4 - day);
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
    const weekNumber = Math.ceil(
      ((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7
    );
    return weekNumber;
  }

  const CustomDayButton = React.useCallback(
    (props: any) => {
      const { day, className, modifiers, ...buttonProps } = props;
      const date: Date = day.date;
      const isToday = Boolean(modifiers?.today);
      const isSelected = Boolean(modifiers?.selected);
      const hasConflict = Boolean(modifiers?.conflict);
      const isMonday = date.getDay() === 1;
      const week = isMonday ? getIsoWeek(date) : null;
      const iso = toISODate(date);
      const preview = previewEarnings[iso];
      const hasShift = hasShiftDates.has(iso);

      return (
        <button
          {...buttonProps}
          className={cn(
            className,
            "w-full h-full rounded-lg transition-colors focus:outline-none focus-visible:outline-none border hover:bg-surface-secondary",
            !hasConflict && "border-border-subtle",
            hasConflict && !isSelected && "border-warning border-dashed",
            hasConflict && isSelected && "ring-1 ring-warning border-transparent",
            isSelected &&
              (hasConflict
                ? "bg-warning-subtle text-text-primary hover:bg-warning-subtle"
                : "bg-brand-gradientStart text-text-inverse hover:bg-brand-gradientStart border-transparent"),
            isToday && "ring-1 ring-brand-highlight",
            isToday && !isSelected && "border-brand-highlight"
          )}
        >
          <div className="relative z-[1] flex flex-col items-center justify-start gap-0.5 w-full h-full p-1">
            {isMonday && (
              <span className="absolute left-1 top-1 text-[9px] leading-none text-text-muted">
                {new Intl.NumberFormat("nb-NO", { minimumIntegerDigits: 2 }).format(
                  week as number
                )}
              </span>
            )}
            <div
              className={cn(
                "w-full text-sm font-semibold text-right pr-1",
                isSelected && !hasConflict
                  ? "text-text-inverse"
                  : hasShift
                    ? "text-brand-highlight"
                    : "text-text-primary"
              )}
            >
              {date.getDate()}
            </div>
            {preview != null && (
              <div
                className={cn(
                  "w-full text-sm font-semibold text-right pr-1",
                  isSelected && !hasConflict ? "text-text-inverse/80" : "text-text-secondary"
                )}
              >
                {formatNOKInt(preview)}
              </div>
            )}
          </div>
        </button>
      );
    },
    [hasShiftDates, previewEarnings]
  );
  const modifiers = React.useMemo(
    () => ({
      conflict: (date: Date) => conflictDates.has(toISODate(date)),
      hasShift: (date: Date) => hasShiftDates.has(toISODate(date)),
    }),
    [conflictDates, hasShiftDates]
  );

  return (
    <DayPicker
      locale={dateFnsLocale}
      className="w-full"
      mode="multiple"
      month={month}
      onMonthChange={onMonthChange}
      selected={selected}
      onSelect={(dates) => onSelectedChange(dates ?? [])}
      styles={{
        root: { width: "100%" },
        months: { width: "100%", maxWidth: "none" },
        month: { width: "100%" },
        month_grid: { width: "100%" },
      }}
      modifiers={modifiers}
      modifiersClassNames={{
        selected: "", // selected handled in CustomDayButton for stronger control
      }}
      weekStartsOn={1}
      showOutsideDays={!disabledOutsideMonth}
      showWeekNumber={false}
      disabled={disabledOutsideMonth ? { before: month, after: new Date(month.getFullYear(), month.getMonth() + 1, 0) } : undefined}
      components={{
        DayButton: CustomDayButton,
      }}
      formatters={{
        formatWeekdayName,
      }}
      classNames={{
        root: "w-full",
        months: "w-full",
        month: "w-full",
        month_caption: "hidden",
        caption_label: "hidden",
        nav: "hidden",
        button_previous: "hidden",
        button_next: "hidden",
        month_grid: "w-full border-collapse",
        weekdays: "hidden",
        weekday: "hidden",
        week: "grid grid-cols-7 gap-1 mb-1",
        day: "relative aspect-square p-0",
        day_button: "w-full h-full rounded-lg hover:bg-surface-secondary transition-colors border border-border-subtle focus:outline-none focus-visible:outline-none",
        outside: disabledOutsideMonth ? "opacity-50 pointer-events-none" : "opacity-50",
        disabled: "text-text-muted opacity-50",
        hidden: "invisible",
      }}
    />
  );
}
