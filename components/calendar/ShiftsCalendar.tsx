"use client";

import * as React from "react";
import { DayPicker, type DayContentProps } from "react-day-picker";
import {
  toISODate,
  formatNOKInt,
  initials,
  type ISODate,
} from "./calendar.utils";
import type { EarningsByDate, HoursByDate } from "./calendar.types";

export type ShiftsCalendarProps = {
  month: Date;
  mode: "money" | "hours";
  earningsByDate: EarningsByDate;
  hoursByDate?: HoursByDate;
  employeesByDate?: Record<ISODate, { name: string; color?: string }[]>;
  onDayClick?: (isoDate: ISODate, hasShifts: boolean) => void;
  onMonthChange?: (month: Date) => void;
};

export function ShiftsCalendar({
  month,
  mode,
  earningsByDate,
  hoursByDate = {},
  employeesByDate = {},
  onDayClick,
  onMonthChange,
}: ShiftsCalendarProps) {
  const CustomDayContent = React.useCallback(
    (props: DayContentProps) => {
      const { date } = props;
      const iso = toISODate(date);
      const earnings = earningsByDate[iso];
      const hours = hoursByDate[iso];
      const employees = employeesByDate[iso] || [];

      return (
        <div className="flex flex-col items-center justify-start gap-0.5 w-full h-full p-1">
          <div className="text-sm font-semibold text-text-primary">
            {date.getDate()}
          </div>
          {mode === "money" && earnings !== undefined && (
            <div className="text-xs text-text-secondary font-medium">
              {formatNOKInt(earnings)}
            </div>
          )}
          {mode === "hours" && hours && (
            <div className="text-xs text-text-secondary leading-tight text-center">
              <div>
                {hours.start}
                {hours.start && "-"}
              </div>
              <div>
                {hours.end}
                {hours.crossesMidnight && "*"}
              </div>
            </div>
          )}
          {employees.length > 0 && (
            <div className="flex gap-0.5 flex-wrap justify-center">
              {employees.slice(0, 3).map((emp, idx) => (
                <div
                  key={idx}
                  className="inline-flex h-4 min-w-4 items-center justify-center rounded-full text-[9px] text-text-inverse px-0.5"
                  style={{ backgroundColor: emp.color || "hsl(var(--info))" }}
                >
                  {initials(emp.name)}
                </div>
              ))}
              {employees.length > 3 && (
                <div className="inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-surface-secondary text-[9px] text-text-muted px-0.5">
                  +{employees.length - 3}
                </div>
              )}
            </div>
          )}
        </div>
      );
    },
    [mode, earningsByDate, hoursByDate, employeesByDate]
  );

  const handleDayClick = React.useCallback(
    (date: Date) => {
      if (onDayClick) {
        const iso = toISODate(date);
        const hasShifts = !!(earningsByDate[iso] || hoursByDate[iso]);
        onDayClick(iso, hasShifts);
      }
    },
    [onDayClick, earningsByDate, hoursByDate]
  );

  return (
    <DayPicker
      mode="default"
      month={month}
      onMonthChange={onMonthChange}
      onDayClick={handleDayClick}
      weekStartsOn={1}
      showOutsideDays
      components={{
        DayContent: CustomDayContent,
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
        day: "aspect-square p-0",
        day_button: "w-full h-full rounded-lg hover:bg-surface-secondary transition-colors",
        outside: "opacity-40",
        today: "bg-surface-secondary",
      }}
    />
  );
}
