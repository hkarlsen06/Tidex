"use client";

import * as React from "react";
import { DayPicker } from "react-day-picker";
import { nb, enUS } from "date-fns/locale";
import { toISODate, type ISODate, formatNOKInt } from "./calendar-utils";
import { getISOWeek, formatWeekdayAbbreviation } from "@/lib/date-utils";
import { cn } from "@/lib/utils";
import { formatInteger } from "@/lib/formatters";
import { useLocale } from "@/lib/i18n/client";

export type SelectDatesCalendarProps = {
  month: Date;
  selected: Date[];
  onSelectedChange: (dates: Date[]) => void;
  conflictDates?: Set<ISODate>;
  hasShiftDates?: Set<ISODate>;
  disabledOutsideMonth?: boolean;
  onMonthChange?: (month: Date) => void;
  _hideCaptionNav?: boolean;
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

  const formatWeekdayName = React.useCallback((date: Date) => {
    return formatWeekdayAbbreviation(date, locale);
  }, [locale]);

  const CustomDayButton = React.useCallback(
    (props: any) => {
      const { day, className, modifiers, ...buttonProps } = props;
      const date: Date = day.date;
      const isToday = Boolean(modifiers?.today);
      const isSelected = Boolean(modifiers?.selected);
      const hasConflict = Boolean(modifiers?.conflict);
      const isMonday = date.getDay() === 1;
      const week = isMonday ? getISOWeek(date) : null;
      const iso = toISODate(date);
      const preview = previewEarnings[iso];
      const hasShift = hasShiftDates.has(iso);

      return (
        <button
          {...buttonProps}
          className={cn(
            className,
            "w-full h-full rounded-lg transition-colors focus:outline-hidden focus-visible:outline-hidden border hover:bg-surface-secondary",
            !hasConflict && "border-border-subtle",
            hasConflict && !isSelected && "border-border dark:border-border-subtle border-dashed opacity-60",
            hasConflict && isSelected && "ring-1 ring-warning border-transparent",
            isSelected &&
              (hasConflict
                ? "bg-warning-subtle text-text-primary hover:bg-warning-subtle"
                : "bg-brand-gradient-start text-text-inverse hover:bg-brand-gradient-start border-transparent"),
            isToday && "ring-1 ring-brand-highlight",
            isToday && !isSelected && "border-brand-highlight"
          )}
        >
          <div className="relative z-1 flex flex-col items-center justify-start gap-0.5 w-full h-full p-1">
            {isMonday && (
              <span className="absolute left-1 top-1 text-[9px] leading-none text-text-muted">
                {formatInteger(week as number)}
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
        selected: "",
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
        weekdays: "grid grid-cols-7 mb-2",
        weekday: "text-text-muted font-normal text-xs text-center py-2 uppercase",
        week: "grid grid-cols-7 gap-1 mb-1",
        day: "relative aspect-square p-0",
        day_button: "w-full h-full rounded-lg hover:bg-surface-secondary transition-colors border border-border-subtle focus:outline-hidden focus-visible:outline-hidden",
        outside: disabledOutsideMonth ? "opacity-50 pointer-events-none" : "opacity-50",
        disabled: "text-text-muted opacity-50",
        hidden: "invisible",
      }}
    />
  );
}
