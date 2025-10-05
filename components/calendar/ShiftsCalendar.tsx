"use client";

import * as React from "react";
import { DayPicker, type DayProps } from "react-day-picker";
import {
  toISODate,
  formatNOKInt,
  initials,
  type ISODate,
} from "./calendar.utils";
import type { EarningsByDate, HoursByDate } from "./calendar.types";

export type ShiftsCalendarProps = {
  month: Date; // controlled
  mode: "money" | "hours"; // controlled
  earningsByDate: EarningsByDate; // required for money mode
  hoursByDate?: HoursByDate; // optional for hours mode
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
  const CustomDay = React.useCallback(
    (props: DayProps) => {
      const { date, ...buttonProps } = props;
      const iso = toISODate(date);
      const earnings = earningsByDate[iso];
      const hours = hoursByDate[iso];
      const employees = employeesByDate[iso] || [];
      const hasShifts = !!(earnings || hours);

      const handleClick = () => {
        if (onDayClick) {
          onDayClick(iso, hasShifts);
        }
      };

      return (
        <button
          {...buttonProps}
          onClick={handleClick}
          className="h-auto min-h-[3rem] w-full p-1 rounded-md hover:bg-surface-secondary focus:ring-2 focus:ring-brand-gradientStart transition-colors flex flex-col items-center justify-start"
        >
          <div className="text-sm font-medium text-text-primary">
            {date.getDate()}
          </div>
          {mode === "money" && earnings !== undefined && (
            <div className="text-xs text-text-secondary leading-tight">
              {formatNOKInt(earnings)} kr
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
            <div className="flex gap-0.5 mt-1 flex-wrap justify-center">
              {employees.slice(0, 3).map((emp, idx) => (
                <div
                  key={idx}
                  className="inline-flex h-5 min-w-5 items-center justify-center rounded-full text-[10px] text-white px-1"
                  style={{
                    backgroundColor: emp.color || "#6366f1",
                  }}
                >
                  {initials(emp.name)}
                </div>
              ))}
              {employees.length > 3 && (
                <div className="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-surface-secondary text-[10px] text-text-muted px-1">
                  +{employees.length - 3}
                </div>
              )}
            </div>
          )}
        </button>
      );
    },
    [mode, earningsByDate, hoursByDate, employeesByDate, onDayClick]
  );

  return (
    <DayPicker
      mode="default"
      month={month}
      onMonthChange={onMonthChange}
      weekStartsOn={1}
      showOutsideDays
      components={{
        Day: CustomDay,
      }}
      classNames={{
        month: "space-y-4",
        caption: "flex justify-center pt-1 relative items-center",
        caption_label: "text-sm font-medium",
        nav: "space-x-1 flex items-center",
        button_previous: "absolute left-1 h-7 w-7 bg-transparent p-0 opacity-50 hover:opacity-100",
        button_next: "absolute right-1 h-7 w-7 bg-transparent p-0 opacity-50 hover:opacity-100",
        month_grid: "w-full border-collapse space-y-1",
        weekdays: "flex",
        weekday: "text-text-muted rounded-md w-full font-normal text-[0.8rem] text-center",
        week: "flex w-full mt-2 border-t border-border-subtle first:border-t-0 pt-2",
        day: "flex-1 text-center text-sm p-0 relative",
        day_outside: "opacity-50",
        day_today: "font-bold",
      }}
    />
  );
}
