"use client";

import * as React from "react";
import { DayPicker } from "react-day-picker";
import { nb, enUS } from "date-fns/locale";
import { motion, AnimatePresence } from "motion/react";
import {
  toISODate,
  formatNOKInt,
  initials,
  type ISODate,
} from "./calendar-utils";
import type { TaxSettings } from "@/lib/shifts/monthlyTotals";
import type { EarningsByDate, HoursByDate } from "./calendar-types";
import { cn } from "@/lib/cn";
import { formatInteger } from "@/lib/formatters";
import { useLocale } from "@/lib/i18n/client";

export type ShiftsCalendarProps = {
  month: Date;
  mode: "money" | "hours";
  earningsByDate: EarningsByDate;
  hoursByDate?: HoursByDate;
  employeesByDate?: Record<ISODate, { name: string; color?: string }[]>;
  /** Dates that have multiple shifts with overlapping hours */
  overlappingDates?: Set<ISODate>;
  onDayClick?: (isoDate: ISODate, hasShifts: boolean) => void;
  onMonthChange?: (month: Date) => void;
  weekNumberPosition?: "top-left" | "bottom-left";
  selectedDate?: ISODate | null;
  /** Set of selected dates for multi-selection mode */
  selectedDates?: Set<ISODate>;
  newlyAddedDates?: Set<string>;
  taxSettings?: TaxSettings;
  /** Deep link: dates to highlight in calendar (from push notification) */
  highlightDates?: Set<string> | null;
  /** When true, cell values animate in with a pop effect (used for stale data sync) */
  animateCellValues?: boolean;
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
  overlappingDates: Set<ISODate>;
  mode: "money" | "hours";
  weekNumberPosition: "top-left" | "bottom-left";
  selectedDate?: ISODate | null;
  selectedDates?: Set<ISODate>;
  newlyAddedDates?: Set<string>;
  taxSettings?: TaxSettings;
  highlightDates?: Set<string> | null;
  animateCellValues?: boolean;
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

function getNetEarningsForDate(
  gross: number | undefined,
  date: Date,
  taxSettings?: TaxSettings
): number | null {
  if (!taxSettings?.enabled || !gross || gross <= 0) return null;

  const month = date.getMonth() + 1;
  let taxPercentage = Number(taxSettings.percentage ?? 0);

  if (taxSettings.halfTaxMonth && month === taxSettings.halfTaxMonth) {
    taxPercentage = taxPercentage / 2;
  }

  const multiplier = 1 - taxPercentage / 100;
  return gross * multiplier;
}

const DayButton = React.memo(function DayButton({
  day,
  className,
  modifiers,
  earningsByDate,
  hoursByDate,
  employeesByDate,
  overlappingDates,
  mode,
  weekNumberPosition,
  selectedDate,
  selectedDates,
  newlyAddedDates,
  taxSettings,
  highlightDates,
  animateCellValues,
  ...buttonProps
}: DayButtonProps) {
  const date: Date = day.date;
  const iso = toISODate(date);
  const earnings = earningsByDate[iso];
  const hours = hoursByDate[iso];
  const employees = employeesByDate[iso] || [];
  const isToday = Boolean(modifiers?.today);
  const isMonday = date.getDay() === 1;
  // Support both single selection (selectedDate) and multi-selection (selectedDates)
  const isSelected = selectedDate === iso || (selectedDates?.has(iso) ?? false);
  const isOutside = Boolean(modifiers?.outside);
  const _isNewlyAdded = newlyAddedDates?.has(iso) ?? false;
  const hasShift =
    earnings !== undefined || hours !== undefined || employees.length > 0;
  const hasOverlap = overlappingDates.has(iso);
  const week = isMonday ? getIsoWeek(date) : null;
  const netEarnings = getNetEarningsForDate(earnings, date, taxSettings);
  const isHighlighted = highlightDates?.has(iso) ?? false;

  return (
    <button
      {...buttonProps}
      data-day={iso}
      aria-pressed={isSelected}
      className={cn(
        className,
        isSelected &&
          "border-brand-gradient-mid bg-brand-gradient-mid/10 text-brand-highlight shadow-app-sm",
        hasOverlap && !isSelected &&
          "border-orange-400/60 bg-orange-500/10 dark:border-orange-500/50 dark:bg-orange-500/15",
        isToday && "ring-1 ring-brand-highlight",
        isToday && !isSelected && "border-brand-highlight",
        isOutside && "opacity-40",
        // Highlight from push notification deep link (consistent with ShiftCard highlighting)
        isHighlighted && "ring-2 ring-emerald-500 dark:ring-emerald-400 animate-pulse-subtle"
      )}
    >
      <div className="relative flex flex-col w-full h-full p-1">
      {isMonday && (
        <span className={`absolute left-1 text-[9px] leading-none text-text-muted ${
          weekNumberPosition === "top-left" ? "top-1" : "bottom-1"
        }`}>
          {formatInteger(week as number)}
        </span>
      )}
      <div
        className={cn(
          "w-full text-xs font-semibold text-right pr-1 mb-1",
          isSelected
            ? "text-brand-highlight"
            : hasOverlap
              ? "text-orange-500 dark:text-orange-400"
              : hasShift
                ? "text-brand-highlight"
                : "text-text-primary"
        )}
        style={{ lineHeight: '12px', height: '12px' }}
      >
        {date.getDate()}
      </div>
      <div
        className={cn(
          "flex-1 flex flex-col justify-center overflow-hidden",
          "items-center"
        )}
      >
        {animateCellValues ? (
          <AnimatePresence mode="wait">
            {mode === "money" && earnings !== undefined && (
              <motion.div
                key={`money-${iso}`}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ type: "spring", bounce: 0.3, duration: 0.4 }}
                className="flex flex-col items-end"
              >
                <div className="text-sm text-text-secondary font-semibold">
                  {formatNOKInt(netEarnings !== null ? netEarnings : earnings)}
                </div>
                {netEarnings !== null && (
                  <div className="text-[11px] text-text-muted leading-tight">
                    {formatNOKInt(earnings)}
                  </div>
                )}
              </motion.div>
            )}
            {mode === "hours" && hours && (
              <motion.div
                key={`hours-${iso}`}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ type: "spring", bounce: 0.3, duration: 0.4 }}
                className="flex flex-col items-center justify-center text-sm font-semibold text-text-secondary leading-tight"
              >
                <div>{hours.start}</div>
                <div>
                  {hours.end}
                  {hours.crossesMidnight && "*"}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        ) : (
          <>
            {mode === "money" && earnings !== undefined && (
              <div className="flex flex-col items-end">
                <div className="text-sm text-text-secondary font-semibold">
                  {formatNOKInt(netEarnings !== null ? netEarnings : earnings)}
                </div>
                {netEarnings !== null && (
                  <div className="text-[11px] text-text-muted leading-tight">
                    {formatNOKInt(earnings)}
                  </div>
                )}
              </div>
            )}
            {mode === "hours" && hours && (
              <div className="flex flex-col items-center justify-center text-sm font-semibold text-text-secondary leading-tight">
                <div>{hours.start}</div>
                <div>
                  {hours.end}
                  {hours.crossesMidnight && "*"}
                </div>
              </div>
            )}
          </>
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
  overlappingDates = new Set(),
  onDayClick,
  onMonthChange,
  weekNumberPosition = "bottom-left",
  selectedDate = null,
  selectedDates,
  newlyAddedDates,
  taxSettings,
  highlightDates,
  animateCellValues = false,
}: ShiftsCalendarProps) {
  const locale = useLocale();
  const dateFnsLocale = locale === 'en' ? enUS : nb;
  const selectedDay = React.useMemo(
    () => (selectedDate ? new Date(`${selectedDate}T00:00:00`) : undefined),
    [selectedDate]
  );

  // Custom formatter for weekday names to show 2-letter abbreviations
  const formatWeekdayName = React.useCallback((date: Date) => {
    const day = date.getDay();
    const shortNames = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
    const shortNamesNb = ['SØ', 'MA', 'TI', 'ON', 'TO', 'FR', 'LØ'];
    const names = locale === 'no' ? shortNamesNb : shortNames;
    return names[day];
  }, [locale]);

  const CustomDayButton = React.useCallback(
    (props: any) => (
      <DayButton
        {...props}
        earningsByDate={earningsByDate}
        hoursByDate={hoursByDate}
        employeesByDate={employeesByDate}
        overlappingDates={overlappingDates}
        mode={mode}
        weekNumberPosition={weekNumberPosition}
        selectedDate={selectedDate}
        selectedDates={selectedDates}
        newlyAddedDates={newlyAddedDates}
        taxSettings={taxSettings}
        highlightDates={highlightDates}
        animateCellValues={animateCellValues}
      />
    ),
    [mode, earningsByDate, hoursByDate, employeesByDate, overlappingDates, weekNumberPosition, selectedDate, selectedDates, newlyAddedDates, taxSettings, highlightDates, animateCellValues]
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

  // Create a stable key from month to force remount when month changes
  // This is needed because with Next.js cacheComponents, the component may be
  // hidden and revealed with a new month prop, but DayPicker's internal state
  // might be stale from the previous render.
  const monthKey = `${month.getFullYear()}-${month.getMonth()}`;

  return (
    <div className="w-full">
      <DayPicker
      key={monthKey}
      locale={dateFnsLocale}
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
        day: "aspect-[1/1.25] p-0",
        day_button: "bg-surface-primary w-full h-full rounded-lg hover:bg-surface-secondary transition-colors border border-border-subtle",
        selected: "",
        outside: "",
        today: "",
      }}
    />
    </div>
  );
}
