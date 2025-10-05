"use client";

import * as React from "react";
import { DayPicker } from "react-day-picker";
import { toISODate, type ISODate } from "./calendar.utils";

export type SelectDatesCalendarProps = {
  month: Date; // controlled
  selected: Date[]; // controlled multi-select
  onSelectedChange: (dates: Date[]) => void;
  conflictDates?: Set<ISODate>; // paint yellow
  hasShiftDates?: Set<ISODate>; // tiny dot
  disabledOutsideMonth?: boolean; // default: true
  onMonthChange?: (month: Date) => void;
};

export function SelectDatesCalendar({
  month,
  selected,
  onSelectedChange,
  conflictDates = new Set(),
  hasShiftDates = new Set(),
  disabledOutsideMonth = true,
  onMonthChange,
}: SelectDatesCalendarProps) {
  const modifiers = React.useMemo(
    () => ({
      conflict: (date: Date) => conflictDates.has(toISODate(date)),
      hasShift: (date: Date) => hasShiftDates.has(toISODate(date)),
    }),
    [conflictDates, hasShiftDates]
  );

  return (
    <DayPicker
      mode="multiple"
      month={month}
      onMonthChange={onMonthChange}
      selected={selected}
      onSelect={(dates) => onSelectedChange(dates ?? [])}
      modifiers={modifiers}
      weekStartsOn={1}
      showWeekNumber
      showOutsideDays={!disabledOutsideMonth}
      disabled={disabledOutsideMonth ? { before: month, after: new Date(month.getFullYear(), month.getMonth() + 1, 0) } : undefined}
      classNames={{
        month: "space-y-4",
        caption: "flex justify-center pt-1 relative items-center",
        caption_label: "text-sm font-medium",
        nav: "space-x-1 flex items-center",
        button_previous: "absolute left-1 h-7 w-7 bg-transparent p-0 opacity-50 hover:opacity-100",
        button_next: "absolute right-1 h-7 w-7 bg-transparent p-0 opacity-50 hover:opacity-100",
        month_grid: "w-full border-collapse space-y-1",
        weekdays: "flex",
        weekday: "text-text-muted rounded-md w-9 font-normal text-[0.8rem]",
        week: "flex w-full mt-2",
        weeknumber: "text-xs text-text-muted w-9 text-center flex items-center justify-center",
        day: "h-9 w-9 text-center text-sm p-0 relative [&:has([aria-selected].day_range_end)]:rounded-r-md [&:has([aria-selected].day_outside)]:bg-accent/50 [&:has([aria-selected])]:bg-accent first:[&:has([aria-selected])]:rounded-l-md last:[&:has([aria-selected])]:rounded-r-md focus-within:relative focus-within:z-20",
        day_button: "h-9 w-9 p-0 font-normal aria-selected:opacity-100 hover:bg-surface-secondary rounded-md transition-colors",
        day_selected: "bg-brand-gradientStart text-white hover:bg-brand-gradientStart hover:text-white focus:bg-brand-gradientStart focus:text-white",
        day_today: "ring-2 ring-brand-gradientStart/50 rounded-md",
        day_outside: disabledOutsideMonth ? "opacity-50 pointer-events-none" : "opacity-50",
        day_disabled: "text-text-muted opacity-50",
        day_hidden: "invisible",
        // Custom modifiers
        day_conflict: "bg-yellow-100 dark:bg-yellow-900/30 ring-1 ring-yellow-400 dark:ring-yellow-600 rounded-md",
        day_hasShift: "after:absolute after:bottom-1 after:left-1/2 after:-translate-x-1/2 after:h-1.5 after:w-1.5 after:rounded-full after:bg-blue-500",
      }}
    />
  );
}
