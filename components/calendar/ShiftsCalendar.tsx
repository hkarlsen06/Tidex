"use client";

import * as React from "react";
import { DayPicker } from "react-day-picker";
import { nb } from "date-fns/locale";
import {
  toISODate,
  formatNOKInt,
  initials,
  type ISODate,
} from "./calendar.utils";
import type { EarningsByDate, HoursByDate } from "./calendar.types";
import { cn } from "@/lib/cn";

export type ShiftsCalendarProps = {
  month: Date;
  mode: "money" | "hours";
  earningsByDate: EarningsByDate;
  hoursByDate?: HoursByDate;
  employeesByDate?: Record<ISODate, { name: string; color?: string }[]>;
  onDayClick?: (isoDate: ISODate, hasShifts: boolean) => void;
  onMonthChange?: (month: Date) => void;
  weekNumberPosition?: "top-left" | "bottom-left";
  selectedDate?: ISODate | null;
};

type DayButtonProps = {
  day: { date: Date };
  className?: string;
  modifiers?: {
    today?: boolean;
    selected?: boolean;
    [key: string]: boolean | undefined;
  };
  earningsByDate: EarningsByDate;
  hoursByDate: HoursByDate;
  employeesByDate: Record<ISODate, { name: string; color?: string }[]>;
  mode: "money" | "hours";
  weekNumberPosition: "top-left" | "bottom-left";
  animationDirection: 'next' | 'previous' | null;
  currentMonth: Date;
  selectedDate?: ISODate | null;
  [key: string]: any;
};

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

// Helper to get animation classes based on direction
function getCellAnimationClasses(direction: 'next' | 'previous' | null): string {
  if (!direction) return '';

  if (direction === 'next') {
    return 'animate-[swipe-in-right_0.4s_ease-in-out]';
  } else {
    return 'animate-[swipe-in-left_0.4s_ease-in-out]';
  }
}

const DayButton = React.memo(function DayButton({
  day,
  className,
  modifiers,
  earningsByDate,
  hoursByDate,
  employeesByDate,
  mode,
  weekNumberPosition,
  animationDirection,
  currentMonth,
  selectedDate,
  ...buttonProps
}: DayButtonProps) {
  const date: Date = day.date;
  const iso = toISODate(date);
  const earnings = earningsByDate[iso];
  const hours = hoursByDate[iso];
  const employees = employeesByDate[iso] || [];
  const isToday = Boolean(modifiers?.today);
  const isMonday = date.getDay() === 1;
  const isSelected = selectedDate === iso;
  const week = isMonday ? getIsoWeek(date) : null;

  // Only animate cells from the current month
  const isCurrentMonth = date.getMonth() === currentMonth.getMonth() &&
                         date.getFullYear() === currentMonth.getFullYear();
  const cellDirection = isCurrentMonth ? animationDirection : null;

  return (
    <button
      {...buttonProps}
      aria-pressed={isSelected}
      className={`${className} ${isToday ? "bg-surface-secondary" : ""} ${
        isSelected
          ? "border-brand-gradientMid bg-brand-gradientMid/10 text-brand-highlight shadow-app-sm"
          : ""
      }`}
    >
      <div className="relative flex flex-col items-center justify-start gap-0.5 w-full h-full p-1 pb-2 sm:pb-1.5 overflow-hidden">
      {isMonday && (
        <span className={`absolute left-1 text-[9px] leading-none text-text-muted ${
          weekNumberPosition === "top-left" ? "top-1" : "bottom-1"
        }`}>
          {new Intl.NumberFormat("nb-NO", { minimumIntegerDigits: 2 }).format(
            week as number
          )}
        </span>
      )}
      <div
        className={cn(
          "w-full text-xs font-semibold text-right pr-1",
          isSelected || isToday ? "text-brand-highlight" : "text-text-primary"
        )}
      >
        {date.getDate()}
      </div>
      {mode === "money" && earnings !== undefined && (
        <div
          key={`earnings-${iso}-${currentMonth.getFullYear()}-${currentMonth.getMonth()}`}
          className={`text-xs text-text-secondary font-medium mt-1 ${getCellAnimationClasses(cellDirection)}`}
        >
          {formatNOKInt(earnings)}
        </div>
      )}
      {mode === "hours" && hours && (
        <div
          key={`hours-${iso}-${currentMonth.getFullYear()}-${currentMonth.getMonth()}`}
          className={`text-[9px] sm:text-[10px] font-medium text-text-secondary leading-none text-center mt-0.5 ${getCellAnimationClasses(cellDirection)}`}
        >
          <div>
            {hours.start}
            {hours.start && "-"}
          </div>
          <div className="mt-0.5">
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
    </button>
  );
});

export function ShiftsCalendar({
  month,
  mode,
  earningsByDate,
  hoursByDate = {},
  employeesByDate = {},
  onDayClick,
  onMonthChange,
  weekNumberPosition = "bottom-left",
  selectedDate = null,
}: ShiftsCalendarProps) {
  const [localDirection, setLocalDirection] = React.useState<'next' | 'previous' | null>(null);
  const [prevMonth, setPrevMonth] = React.useState(month);
  const selectedDay = React.useMemo(
    () => (selectedDate ? new Date(`${selectedDate}T00:00:00`) : undefined),
    [selectedDate]
  );

  // Track month changes and determine direction locally
  React.useEffect(() => {
    if (month.getTime() !== prevMonth.getTime()) {
      const isForward = month > prevMonth;
      setLocalDirection(isForward ? 'next' : 'previous');
      setPrevMonth(month);
    }
  }, [month, prevMonth]);

  React.useEffect(() => {
    if (!localDirection) {
      return;
    }
    const timeout = setTimeout(() => setLocalDirection(null), 450);
    return () => clearTimeout(timeout);
  }, [localDirection]);

  const CustomDayButton = React.useCallback(
    (props: any) => (
      <DayButton
        {...props}
        earningsByDate={earningsByDate}
        hoursByDate={hoursByDate}
        employeesByDate={employeesByDate}
        mode={mode}
        weekNumberPosition={weekNumberPosition}
        animationDirection={localDirection}
        currentMonth={month}
        selectedDate={selectedDate}
      />
    ),
    [mode, earningsByDate, hoursByDate, employeesByDate, weekNumberPosition, localDirection, month, selectedDate]
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
    <div className="w-full">
      <DayPicker
      locale={nb}
      month={month}
      mode="single"
      selected={selectedDay}
      onMonthChange={onMonthChange}
      onDayClick={handleDayClick}
      weekStartsOn={1}
      showOutsideDays
      components={{
        DayButton: CustomDayButton,
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
        day_button: "w-full h-full rounded-lg hover:bg-surface-secondary transition-colors border border-border-subtle",
        selected: "",
        outside: "opacity-40",
        today: "",
      }}
    />
    </div>
  );
}
