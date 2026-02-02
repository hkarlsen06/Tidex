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
import { impactHaptic } from "@/lib/capacitor/haptics";

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
  /** Long-press + drag selection commits a contiguous date range */
  onSelectDateRange?: (start: ISODate, end: ISODate) => void;
  /** Optional overrides for gesture thresholds */
  gestureConfig?: Partial<GestureConfig>;
  /** Optional instrumentation hook for gesture metrics */
  onGestureMetric?: (metric: GestureMetric) => void;
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

// Touch gesture state machine for paging vs. long-press selection.
type GestureMode = "idle" | "pressing" | "paging" | "selecting";

export type GestureConfig = {
  touchSlopPx: number;
  longPressMs: number;
  horizontalDominanceRatio: number;
  pagingDistancePx: number;
  pagingVelocityPxPerMs: number;
  minimumFlickDistancePx: number;
  cellInnerInsetPx: number;
};

export type GestureMetric = {
  type:
    | "pagingStarted"
    | "pagingCompleted"
    | "pagingCanceled"
    | "selectionStarted"
    | "selectionCompleted"
    | "selectionCanceled"
    | "longPressCanceled";
  data?: Record<string, number | string | boolean | null>;
};

const DEFAULT_GESTURE_CONFIG: GestureConfig = {
  touchSlopPx: 8,
  longPressMs: 220,
  horizontalDominanceRatio: 1.5,
  pagingDistancePx: 40,
  pagingVelocityPxPerMs: 0.7,
  minimumFlickDistancePx: 15,
  cellInnerInsetPx: 4,
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
        // Today indicator: thick border (underneath selection ring)
        isToday && "border-2 border-brand-highlight",
        // Selected state: purple border (using shadow-[inset] to avoid clipping on edge cells)
        isSelected &&
          "shadow-[inset_0_0_0_2px_rgb(139,92,246)] dark:shadow-[inset_0_0_0_2px_rgb(167,139,250)] bg-violet-500/10 dark:bg-violet-500/15",
        // Overlap indicator (only when not selected)
        hasOverlap && !isSelected &&
          "border-orange-400/60 bg-orange-500/10 dark:border-orange-500/50 dark:bg-orange-500/15",
        isOutside && "opacity-40",
        // Highlight from push notification deep link (using inset shadow to avoid clipping on edge cells)
        isHighlighted && !isSelected && "shadow-[inset_0_0_0_2px_rgb(16,185,129)] dark:shadow-[inset_0_0_0_2px_rgb(52,211,153)] animate-pulse-subtle"
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
            ? "text-violet-600 dark:text-violet-400"
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
  onSelectDateRange,
  gestureConfig,
  onGestureMetric,
}: ShiftsCalendarProps) {
  const locale = useLocale();
  const dateFnsLocale = locale === 'en' ? enUS : nb;
  const calendarRef = React.useRef<HTMLDivElement>(null);
  const suppressClickRef = React.useRef(false);
  const [dragSelectedDates, setDragSelectedDates] = React.useState<Set<ISODate> | null>(null);
  const [isGestureLocked, setIsGestureLocked] = React.useState(false);
  const config = React.useMemo(
    () => ({ ...DEFAULT_GESTURE_CONFIG, ...gestureConfig }),
    [gestureConfig]
  );
  const displaySelectedDate = dragSelectedDates ? null : selectedDate;
  const displaySelectedDates = React.useMemo(() => {
    if (!dragSelectedDates) return selectedDates;
    const merged = new Set<ISODate>();
    if (selectedDate) merged.add(selectedDate);
    selectedDates?.forEach((iso) => merged.add(iso));
    dragSelectedDates.forEach((iso) => merged.add(iso));
    return merged;
  }, [dragSelectedDates, selectedDate, selectedDates]);
  const selectedDay = React.useMemo(
    () => (displaySelectedDate ? new Date(`${displaySelectedDate}T00:00:00`) : undefined),
    [displaySelectedDate]
  );

  // Custom formatter for weekday names to show 2-letter abbreviations
  const formatWeekdayName = React.useCallback((date: Date) => {
    const day = date.getDay();
    const shortNames = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
    const shortNamesNb = ['SØ', 'MA', 'TI', 'ON', 'TO', 'FR', 'LØ'];
    const names = locale === 'no' ? shortNamesNb : shortNames;
    return names[day];
  }, [locale]);

  const reportMetric = React.useCallback(
    (metric: GestureMetric) => {
      onGestureMetric?.(metric);
      if (typeof window !== "undefined") {
        window.dispatchEvent(new CustomEvent("calendar-gesture", { detail: metric }));
      }
    },
    [onGestureMetric]
  );

  const hasShiftsFor = React.useCallback(
    (iso: ISODate) =>
      Object.prototype.hasOwnProperty.call(earningsByDate, iso) ||
      Object.prototype.hasOwnProperty.call(hoursByDate, iso),
    [earningsByDate, hoursByDate]
  );

  const buildRange = React.useCallback(
    (start: ISODate, end: ISODate) => {
      const startDate = new Date(`${start}T00:00:00`);
      const endDate = new Date(`${end}T00:00:00`);
      const step = startDate <= endDate ? 1 : -1;
      const result: ISODate[] = [];
      const cursor = new Date(startDate);

      while ((step > 0 && cursor <= endDate) || (step < 0 && cursor >= endDate)) {
        const iso = toISODate(cursor);
        if (hasShiftsFor(iso)) {
          result.push(iso);
        }
        cursor.setDate(cursor.getDate() + step);
      }

      return result;
    },
    [hasShiftsFor]
  );

  const hitTestDayCell = React.useCallback(
    (x: number, y: number) => {
      if (typeof document === "undefined") return null;
      const target = document.elementFromPoint(x, y);
      if (!(target instanceof HTMLElement)) return null;
      const button = target.closest("button[data-day]");
      if (!button) return null;
      if (calendarRef.current && !calendarRef.current.contains(button)) return null;
      const rect = button.getBoundingClientRect();
      const inset = config.cellInnerInsetPx;
      if (
        x < rect.left + inset ||
        x > rect.right - inset ||
        y < rect.top + inset ||
        y > rect.bottom - inset
      ) {
        return null;
      }
      const iso = button.getAttribute("data-day");
      return iso as ISODate | null;
    },
    [config.cellInnerInsetPx]
  );

  const gestureStateRef = React.useRef<{
    mode: GestureMode;
    pointerId: number | null;
    startX: number;
    startY: number;
    lastX: number;
    lastY: number;
    startTime: number;
    lastTime: number;
    velocityX: number;
    startCell: ISODate | null;
    anchorCell: ISODate | null;
    lastHoverCell: ISODate | null;
    longPressTimer: ReturnType<typeof setTimeout> | null;
  }>({
    mode: "idle",
    pointerId: null,
    startX: 0,
    startY: 0,
    lastX: 0,
    lastY: 0,
    startTime: 0,
    lastTime: 0,
    velocityX: 0,
    startCell: null,
    anchorCell: null,
    lastHoverCell: null,
    longPressTimer: null,
  });

  const clearLongPressTimer = React.useCallback(() => {
    const state = gestureStateRef.current;
    if (state.longPressTimer) {
      clearTimeout(state.longPressTimer);
      state.longPressTimer = null;
    }
  }, []);

  const resetGesture = React.useCallback((clearPreview: boolean) => {
    const state = gestureStateRef.current;
    state.mode = "idle";
    state.pointerId = null;
    state.startCell = null;
    state.anchorCell = null;
    state.lastHoverCell = null;
    state.velocityX = 0;
    clearLongPressTimer();
    if (clearPreview) {
      setDragSelectedDates(null);
    }
    setIsGestureLocked(false);
  }, [clearLongPressTimer]);

  const handleDayClick = React.useCallback(
    (date: Date) => {
      if (!onDayClick) return;
      const iso = toISODate(date);
      onDayClick(iso, hasShiftsFor(iso));
    },
    [onDayClick, hasShiftsFor]
  );

  const handlePointerDown = React.useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (event.pointerType !== "touch") return;
      const state = gestureStateRef.current;
      if (state.pointerId !== null) return;
      state.pointerId = event.pointerId;
      state.mode = "pressing";
      state.startX = event.clientX;
      state.startY = event.clientY;
      state.lastX = event.clientX;
      state.lastY = event.clientY;
      state.startTime = event.timeStamp;
      state.lastTime = event.timeStamp;
      state.velocityX = 0;
      state.startCell = hitTestDayCell(event.clientX, event.clientY);
      state.anchorCell = null;
      state.lastHoverCell = null;
      suppressClickRef.current = true;

      if (onSelectDateRange && state.startCell && hasShiftsFor(state.startCell)) {
        event.preventDefault();
        state.longPressTimer = setTimeout(() => {
          const current = gestureStateRef.current;
          if (current.mode !== "pressing") return;
          if (!current.startCell) return;
          const dx = current.lastX - current.startX;
          const dy = current.lastY - current.startY;
          if (Math.hypot(dx, dy) > config.touchSlopPx * 3) return;
          current.mode = "selecting";
          const startCell = current.startCell;
          current.anchorCell = startCell;
          const currentCell = hitTestDayCell(current.lastX, current.lastY);
          current.lastHoverCell = currentCell ?? startCell;
          const range = buildRange(startCell, current.lastHoverCell);
          setDragSelectedDates(new Set(range));
          setIsGestureLocked(true);
          impactHaptic("heavy");
          reportMetric({
            type: "selectionStarted",
            data: { anchor: startCell },
          });
        }, config.longPressMs);
      }

      event.currentTarget.setPointerCapture(event.pointerId);
    },
    [buildRange, config.longPressMs, config.touchSlopPx, hasShiftsFor, hitTestDayCell, onSelectDateRange, reportMetric]
  );

  const handlePointerMove = React.useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (event.pointerType !== "touch") return;
      const state = gestureStateRef.current;
      if (state.pointerId !== event.pointerId) return;

      const dx = event.clientX - state.startX;
      const dy = event.clientY - state.startY;
      const adx = Math.abs(dx);
      const ady = Math.abs(dy);
      const dt = Math.max(1, event.timeStamp - state.lastTime);
      state.velocityX = (event.clientX - state.lastX) / dt;
      state.lastX = event.clientX;
      state.lastY = event.clientY;
      state.lastTime = event.timeStamp;

      if (state.mode === "pressing") {
        if (Math.hypot(dx, dy) < config.touchSlopPx) return;
        const isHorizontal = adx > ady * config.horizontalDominanceRatio;
        const byVelocity = Math.abs(state.velocityX) > config.pagingVelocityPxPerMs;
        const shouldPage = isHorizontal && (adx > config.pagingDistancePx || byVelocity);
        if (shouldPage) {
          clearLongPressTimer();
          reportMetric({
            type: "longPressCanceled",
            data: { dx, dy },
          });
          state.mode = "paging";
          setIsGestureLocked(true);
          reportMetric({
            type: "pagingStarted",
            data: {
              dx,
              velocityX: state.velocityX,
              reason: byVelocity ? "velocity" : "distance",
            },
          });
          event.preventDefault();
        }
        return;
      }

      if (state.mode === "paging") {
        event.preventDefault();
        return;
      }

      if (state.mode === "selecting") {
        event.preventDefault();
        const currentCell = hitTestDayCell(event.clientX, event.clientY);
        if (!currentCell || !state.anchorCell || !hasShiftsFor(currentCell)) return;
        if (currentCell === state.lastHoverCell) return;
        state.lastHoverCell = currentCell;
        const range = buildRange(state.anchorCell, currentCell);
        setDragSelectedDates(new Set(range));
      }
    },
    [
      buildRange,
      clearLongPressTimer,
      config.horizontalDominanceRatio,
      config.pagingDistancePx,
      config.pagingVelocityPxPerMs,
      config.touchSlopPx,
      hasShiftsFor,
      hitTestDayCell,
      reportMetric,
    ]
  );

  const handlePointerUp = React.useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (event.pointerType !== "touch") return;
      const state = gestureStateRef.current;
      if (state.pointerId !== event.pointerId) return;
      clearLongPressTimer();

      const dx = event.clientX - state.startX;
      const dy = event.clientY - state.startY;
      const adx = Math.abs(dx);
      const velocityX = state.velocityX;

      if (state.mode === "paging") {
        const width = calendarRef.current?.getBoundingClientRect().width ?? 0;
        const shouldPage = width > 0 && adx > width * 0.25;
        const shouldFlick =
          Math.abs(velocityX) > config.pagingVelocityPxPerMs &&
          adx > config.minimumFlickDistancePx;

        if (onMonthChange && (shouldPage || shouldFlick)) {
          const direction = dx < 0 ? 1 : -1;
          const nextMonth = new Date(month.getFullYear(), month.getMonth() + direction, 1);
          onMonthChange(nextMonth);
          reportMetric({
            type: "pagingCompleted",
            data: { dx, velocityX, direction },
          });
        } else {
          reportMetric({
            type: "pagingCanceled",
            data: { dx, velocityX },
          });
        }
        resetGesture(true);
      } else if (state.mode === "selecting") {
        const endCell =
          hitTestDayCell(event.clientX, event.clientY) ??
          state.lastHoverCell ??
          state.anchorCell;
        if (state.anchorCell && endCell && onSelectDateRange) {
          onSelectDateRange(state.anchorCell, endCell);
          const range = buildRange(state.anchorCell, endCell);
          reportMetric({
            type: "selectionCompleted",
            data: { size: range.length, dx, dy },
          });
        } else {
          reportMetric({
            type: "selectionCanceled",
            data: { dx, dy },
          });
        }
        resetGesture(true);
      } else {
        const tapCell = hitTestDayCell(event.clientX, event.clientY) ?? state.startCell;
        if (tapCell && onDayClick) {
          onDayClick(tapCell, hasShiftsFor(tapCell));
        }
        resetGesture(false);
      }

      suppressClickRef.current = true;
      setTimeout(() => {
        suppressClickRef.current = false;
      }, 0);
    },
    [
      buildRange,
      clearLongPressTimer,
      config.minimumFlickDistancePx,
      config.pagingVelocityPxPerMs,
      hasShiftsFor,
      hitTestDayCell,
      month,
      onDayClick,
      onMonthChange,
      onSelectDateRange,
      reportMetric,
      resetGesture,
    ]
  );

  const handlePointerCancel = React.useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (event.pointerType !== "touch") return;
      const state = gestureStateRef.current;
      if (state.pointerId !== event.pointerId) return;
      clearLongPressTimer();
      if (state.mode === "selecting") {
        const endCell = state.lastHoverCell ?? state.anchorCell;
        if (state.anchorCell && endCell && onSelectDateRange) {
          onSelectDateRange(state.anchorCell, endCell);
          const range = buildRange(state.anchorCell, endCell);
          reportMetric({
            type: "selectionCompleted",
            data: { size: range.length, canceled: true },
          });
        } else {
          reportMetric({ type: "selectionCanceled" });
        }
      } else if (state.mode === "paging") {
        reportMetric({ type: "pagingCanceled" });
      }
      resetGesture(true);
      suppressClickRef.current = false;
    },
    [buildRange, clearLongPressTimer, onSelectDateRange, reportMetric, resetGesture]
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

  React.useEffect(() => {
    const node = calendarRef.current;
    const win = node?.ownerDocument?.defaultView ?? (typeof window !== "undefined" ? window : null);
    if (!win) return undefined;
    const handleTouchStart = (event: TouchEvent) => {
      if (!onSelectDateRange) return;
      const touch = event.touches[0];
      if (!touch) return;
      const cell = hitTestDayCell(touch.clientX, touch.clientY);
      if (!cell || !hasShiftsFor(cell)) return;
      if (event.cancelable) {
        event.preventDefault();
      }
    };
    const handleTouchMove = (event: TouchEvent) => {
      const state = gestureStateRef.current;
      if (state.pointerId === null) return;
      if (state.mode === "selecting" || state.mode === "paging") {
        if (event.cancelable) {
          event.preventDefault();
        }
      }
    };

    win.addEventListener("touchstart", handleTouchStart, { passive: false, capture: true });
    win.addEventListener("touchmove", handleTouchMove, { passive: false, capture: true });
    return () => {
      win.removeEventListener("touchstart", handleTouchStart, true);
      win.removeEventListener("touchmove", handleTouchMove, true);
    };
  }, [hasShiftsFor, hitTestDayCell, onSelectDateRange]);

  React.useEffect(() => {
    return () => {
      clearLongPressTimer();
    };
  }, [clearLongPressTimer]);

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
        selectedDate={displaySelectedDate}
        selectedDates={displaySelectedDates}
        newlyAddedDates={newlyAddedDates}
        taxSettings={taxSettings}
        highlightDates={highlightDates}
        animateCellValues={animateCellValues}
      />
    ),
    [mode, earningsByDate, hoursByDate, employeesByDate, overlappingDates, weekNumberPosition, displaySelectedDate, displaySelectedDates, newlyAddedDates, taxSettings, highlightDates, animateCellValues]
  );

  // Create a stable key from month to force remount when month changes
  // This is needed because with Next.js cacheComponents, the component may be
  // hidden and revealed with a new month prop, but DayPicker's internal state
  // might be stale from the previous render.
  const monthKey = `${month.getFullYear()}-${month.getMonth()}`;

  return (
    <div
      ref={calendarRef}
      className="w-full select-none"
      style={{ touchAction: isGestureLocked ? "none" : "pan-y" }}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerCancel}
      onClickCapture={handleClickCapture}
    >
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
