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
  const calendarRef = React.useRef<HTMLDivElement>(null);
  const suppressClickRef = React.useRef(false);
  const pointerStateRef = React.useRef({
    pointerId: null as number | null,
    startX: 0,
    startY: 0,
    startCell: null as ISODate | null,
    moved: false,
  });
  const touchSlopPx = 8;
  const cellInnerInsetPx = 4;

  const formatWeekdayName = React.useCallback((date: Date) => {
    return formatWeekdayAbbreviation(date, locale);
  }, [locale]);

  const selectedSet = React.useMemo(() => {
    const set = new Set<ISODate>();
    selected.forEach((date) => set.add(toISODate(date)));
    return set;
  }, [selected]);

  const hitTestDayCell = React.useCallback(
    (x: number, y: number) => {
      if (typeof document === "undefined") return null;
      const target = document.elementFromPoint(x, y);
      if (!(target instanceof HTMLElement)) return null;
      const button = target.closest("button[data-day]");
      if (!button) return null;
      if (calendarRef.current && !calendarRef.current.contains(button)) return null;
      if (button instanceof HTMLButtonElement && button.disabled) return null;
      const rect = button.getBoundingClientRect();
      if (
        x < rect.left + cellInnerInsetPx ||
        x > rect.right - cellInnerInsetPx ||
        y < rect.top + cellInnerInsetPx ||
        y > rect.bottom - cellInnerInsetPx
      ) {
        return null;
      }
      const iso = button.getAttribute("data-day");
      return iso as ISODate | null;
    },
    [cellInnerInsetPx]
  );

  const toggleSelection = React.useCallback(
    (iso: ISODate) => {
      const exists = selectedSet.has(iso);
      const next = exists
        ? selected.filter((date) => toISODate(date) !== iso)
        : [...selected, new Date(`${iso}T00:00:00`)];
      next.sort((a, b) => a.getTime() - b.getTime());
      onSelectedChange(next);
    },
    [onSelectedChange, selected, selectedSet]
  );

  const handlePointerDown = React.useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (event.pointerType !== "touch") return;
      const state = pointerStateRef.current;
      if (state.pointerId !== null) return;
      state.pointerId = event.pointerId;
      state.startX = event.clientX;
      state.startY = event.clientY;
      state.startCell = hitTestDayCell(event.clientX, event.clientY);
      state.moved = false;
    },
    [hitTestDayCell]
  );

  const handlePointerMove = React.useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (event.pointerType !== "touch") return;
      const state = pointerStateRef.current;
      if (state.pointerId !== event.pointerId) return;
      if (state.moved) return;
      const dx = event.clientX - state.startX;
      const dy = event.clientY - state.startY;
      if (Math.hypot(dx, dy) > touchSlopPx) {
        state.moved = true;
      }
    },
    [touchSlopPx]
  );

  const handlePointerUp = React.useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (event.pointerType !== "touch") return;
      const state = pointerStateRef.current;
      if (state.pointerId !== event.pointerId) return;
      state.pointerId = null;
      const startCell = state.startCell;
      state.startCell = null;
      if (state.moved) {
        state.moved = false;
        return;
      }
      const endCell = hitTestDayCell(event.clientX, event.clientY);
      const targetCell = endCell ?? startCell;
      if (targetCell) {
        toggleSelection(targetCell);
      }
      suppressClickRef.current = true;
      setTimeout(() => {
        suppressClickRef.current = false;
      }, 0);
      state.moved = false;
    },
    [hitTestDayCell, toggleSelection]
  );

  const handlePointerCancel = React.useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (event.pointerType !== "touch") return;
      const state = pointerStateRef.current;
      if (state.pointerId !== event.pointerId) return;
      state.pointerId = null;
      state.startCell = null;
      state.moved = false;
      suppressClickRef.current = false;
    },
    []
  );

  const handleClickCapture = React.useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      if (!suppressClickRef.current) return;
      const target = event.target instanceof HTMLElement
        ? event.target.closest("button[data-day]")
        : null;
      if (target) {
        event.preventDefault();
        event.stopPropagation();
      }
      suppressClickRef.current = false;
    },
    []
  );

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
            "w-full h-full rounded-lg transition-colors focus:outline-none focus-visible:outline-none border hover:bg-surface-secondary",
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
    <div
      ref={calendarRef}
      className="w-full select-none"
      style={{ touchAction: "pan-y" }}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerCancel}
      onClickCapture={handleClickCapture}
    >
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
          day_button: "w-full h-full rounded-lg hover:bg-surface-secondary transition-colors border border-border-subtle focus:outline-none focus-visible:outline-none",
          outside: disabledOutsideMonth ? "opacity-50 pointer-events-none" : "opacity-50",
          disabled: "text-text-muted opacity-50",
          hidden: "invisible",
        }}
      />
    </div>
  );
}
