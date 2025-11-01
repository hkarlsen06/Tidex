"use client";

import { useMemo, useState, useCallback, useTransition, useRef, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import dynamic from "next/dynamic";
import confetti from "canvas-confetti";

import ShiftCard from "@/components/app/ShiftCard";
import ShiftMoveCard from "./ShiftMoveCard";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/app/Card";
import { CalendarSkeleton } from "@/components/app/CalendarSkeleton";
import { Button } from "@/components/app/Button";
import { ShiftWithComputations, UserSettings, SupplementRule } from "@/lib/payroll";
import ShiftDetails from "@/components/shifts/ShiftDetails";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";
import { updateShift } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { copyShifts } from "@/app/[locale]/(app)/shifts/_actions/copyShifts";
import { moveSeriesShift } from "@/app/[locale]/(app)/shifts/_actions/moveSeriesShift";
import { useNavigationFeedback } from "@/components/app/navigation-feedback";
import { useMonth } from "@/components/app/MonthContext";
import type { ISODate } from "@/components/calendar/calendar.types";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from "@/components/app/Dialog";
import { IconArrowRight, IconArrowLeft } from "@tabler/icons-react";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";
import type { Locale } from "@/lib/i18n/config";
import { formatCurrency, formatInteger } from "@/lib/formatters";
import { getDateFormatter } from "@/lib/i18n/locale";

// Lazy load the calendar to reduce initial bundle size (~40KB savings)
const MonthlyEarningsCalendar = dynamic(
  () => import("./MonthlyEarningsCalendar").then((mod) => ({ default: mod.MonthlyEarningsCalendar })),
  {
    loading: () => <CalendarSkeleton />,
    ssr: true
  }
);

export type WeekGroup = {
  id: string;
  label: string;
  totalGross: number;
  shifts: ShiftWithComputations[];
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
  return { weekNumber, year: d.getUTCFullYear() };
}

function formatWeekTotal(value: number) {
  return formatCurrency(value);
}

// Combined filter and group operation for better performance
function filterAndGroupByWeek(
  shifts: ShiftWithComputations[],
  month: Date
): WeekGroup[] {
  const groups: WeekGroup[] = [];
  const map = new Map<string, WeekGroup>();
  const targetMonth = month.getMonth();
  const targetYear = month.getFullYear();

  // Single pass: filter AND group simultaneously
  for (const shift of shifts) {
    const date = parseISODate(shift.shift_date);

    // Filter inline
    if (date.getUTCMonth() !== targetMonth || date.getUTCFullYear() !== targetYear) {
      continue;
    }

    // Group inline
    const { weekNumber, year } = getIsoWeek(date);
    const id = `${year}-${weekNumber}`;

    let group = map.get(id);
    if (!group) {
      group = {
        id,
        label: `${formatInteger(weekNumber)}`,
        totalGross: 0,
        shifts: [],
      };
      map.set(id, group);
      groups.push(group);
    }

    group.shifts.push(shift);
    group.totalGross += shift.computed.gross;
  }

  // Sort shifts within each week by date
  for (const group of groups) {
    group.shifts.sort((a, b) => a.shift_date.localeCompare(b.shift_date));
  }

  // Sort week groups chronologically by year and week number
  groups.sort((a, b) => {
    const [yearA, weekA] = a.id.split('-').map(Number);
    const [yearB, weekB] = b.id.split('-').map(Number);

    if (yearA !== yearB) {
      return yearA - yearB;
    }
    return weekA - weekB;
  });

  return groups;
}

function startOfMonth(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function capitalize(input: string) {
  return input ? input.charAt(0).toUpperCase() + input.slice(1) : "";
}

// Parse ISO date string consistently as UTC to avoid timezone issues
function parseISODate(isoDate: string): Date {
  return new Date(`${isoDate}T00:00:00Z`);
}

function formatShiftRange(shift: ShiftWithComputations) {
  return `${shift.start_time}–${shift.end_time}`;
}

function buildHoursPreview(shifts: ShiftWithComputations[]) {
  if (shifts.length === 0) return "";
  if (shifts.length === 1) return formatShiftRange(shifts[0]);

  // For multiple shifts, show earliest start and latest end time
  const times = shifts.map(shift => ({
    start: shift.start_time,
    end: shift.end_time
  }));

  const earliestStart = times.reduce((min, t) => t.start < min ? t.start : min, times[0].start);
  const latestEnd = times.reduce((max, t) => t.end > max ? t.end : max, times[0].end);

  return `${earliestStart}–${latestEnd}`;
}

type CalendarCellPreviewProps = {
  isoDate: ISODate | null;
  hours: string;
  placeholder: string;
  variant: "source" | "target";
  sourceDate?: ISODate | null;
  locale: Locale;
  t: any;
};

function CalendarCellPreview({
  isoDate,
  hours,
  placeholder,
  variant,
  sourceDate,
  locale,
  t,
}: CalendarCellPreviewProps) {
  const moveDateFormatter = useMemo(() => {
    return getDateFormatter(locale, {
      day: "2-digit",
      month: "long",
    });
  }, [locale]);

  const date = isoDate ? parseISODate(isoDate) : null;
  const dayNumber = date ? date.getUTCDate() : null;
  const monthLabel = date
    ? capitalize(moveDateFormatter.format(date).split(" ").slice(1).join(" "))
    : "";

  const source = sourceDate ? parseISODate(sourceDate) : null;
  const isDifferentMonth = source && date
    ? source.getUTCMonth() !== date.getUTCMonth() || source.getUTCFullYear() !== date.getUTCFullYear()
    : false;
  const isTargetWithDifferentMonth = variant === "target" && isDifferentMonth;
  const hasHours = Boolean(hours.trim());
  const displayHours = hasHours ? hours : placeholder;
  const timeElements = hasHours
    ? displayHours.split("\n").flatMap((line, index) => {
        const trimmed = line.trim();
        if (!trimmed) {
          return [];
        }
        if (trimmed.includes("–")) {
          const [start, end] = trimmed.split("–").map((part) => part.trim());
          return [
            <span key={`start-${index}`} className="text-xl font-semibold leading-tight">
              {`${start} –`}
            </span>,
            <span key={`end-${index}`} className="text-xl font-semibold leading-tight">
              {end}
            </span>,
          ];
        }
        return [
          <span key={`extra-${index}`} className="text-sm font-medium text-text-muted leading-tight">
            {trimmed}
          </span>,
        ];
      })
    : [
        <span key="placeholder" className="text-base font-semibold text-text-muted leading-tight">
          {placeholder}
        </span>,
      ];

  const baseClasses =
    "flex h-28 w-24 flex-col justify-start rounded-2xl border bg-surface-primary text-center shadow-app-sm";
  const variantClasses =
    variant === "target"
      ? "border-brand-gradientMid bg-brand-gradientMid/10"
      : "border-border-subtle";
  const dayNumberClasses = cn(
    "w-full text-2xl font-bold text-right pr-1",
    variant === "target" ? "text-brand-highlight" : "text-text-primary"
  );

  return (
    <div className="flex flex-col items-center gap-1">
      <div className={`${baseClasses} ${variantClasses}`}>
        <div className="flex flex-1 flex-col items-center justify-start gap-1 p-1 pb-1.5">
          <div className={dayNumberClasses}>
            {dayNumber !== null ? dayNumber : "--"}
          </div>
          {dayNumber ? (
            <div className="flex flex-1 flex-col items-center justify-center gap-1 text-text-secondary">
              {timeElements}
            </div>
          ) : (
            <div className="flex flex-1 items-center justify-center text-xs font-medium text-text-muted">
              {t.pages.shifts.calendar.selectDate}
            </div>
          )}
        </div>
      </div>
      <div className={`text-[11px] font-medium uppercase tracking-[0.14em] ${isTargetWithDifferentMonth ? "text-brand-highlight" : "text-text-muted"}`}>
        {monthLabel || ""}
      </div>
    </div>
  );
}

type MoveShiftModalProps = {
  open: boolean;
  sourceDate: ISODate | null;
  targetDate: ISODate | null;
  shifts: ShiftWithComputations[];
  selectedIds: string[];
  onToggleShift: (id: string) => void;
  onConfirm: () => void;
  onCancel: () => void;
  isSubmitting: boolean;
  error?: string | null;
  userSettings: UserSettings;
  presetRules: SupplementRule[];
  locale: Locale;
  t: any;
};

function MoveShiftModal({
  open,
  sourceDate,
  targetDate,
  shifts,
  selectedIds,
  onToggleShift,
  onConfirm,
  onCancel,
  isSubmitting,
  error,
  userSettings,
  presetRules,
  locale,
  t,
}: MoveShiftModalProps) {
  const multipleShifts = shifts.length > 1;
  const hasSourceShifts = shifts.length > 0;
  const selectedShifts =
    selectedIds.length > 0
      ? shifts.filter((shift) => selectedIds.includes(shift.id))
      : shifts.length === 1
      ? shifts
      : [];
  const hoursPreview = buildHoursPreview(selectedShifts);
  const sourcePlaceholder = hasSourceShifts ? t.pages.shifts.calendar.selectShifts : t.pages.shifts.calendar.noShifts;
  const targetPlaceholder = targetDate
    ? selectedShifts.length > 0
      ? t.pages.shifts.calendar.hoursMovingHere
      : t.pages.shifts.calendar.selectShifts
    : t.pages.shifts.calendar.selectDate;
  const targetHours =
    selectedShifts.length > 0 && targetDate ? hoursPreview : "";
  const isReverseDirection = useMemo(() => {
    if (!sourceDate || !targetDate) {
      return false;
    }
    return parseISODate(targetDate).getTime() < parseISODate(sourceDate).getTime();
  }, [sourceDate, targetDate]);

  const fromSection = (
    <div className="flex flex-col items-center gap-2">
      <span className="text-xs font-semibold uppercase tracking-[0.2em] text-text-muted">
        {t.pages.shifts.calendar.from}
      </span>
      <CalendarCellPreview
        isoDate={sourceDate}
        hours={hoursPreview}
        placeholder={sourcePlaceholder}
        variant="source"
        sourceDate={sourceDate}
        locale={locale}
        t={t}
      />
    </div>
  );

  const toSection = (
    <div className="flex flex-col items-center gap-2">
      <span className="text-xs font-semibold uppercase tracking-[0.2em] text-text-muted">
        {t.pages.shifts.calendar.to}
      </span>
      <CalendarCellPreview
        isoDate={targetDate}
        hours={targetHours}
        placeholder={targetPlaceholder}
        variant="target"
        sourceDate={sourceDate}
        locale={locale}
        t={t}
      />
    </div>
  );

  const directionArrow = isReverseDirection ? (
    <IconArrowLeft className="h-8 w-8 text-brand-highlight" aria-hidden="true" />
  ) : (
    <IconArrowRight className="h-8 w-8 text-brand-highlight" aria-hidden="true" />
  );

  return (
    <Dialog open={open} onOpenChange={(nextOpen) => { if (!nextOpen && !isSubmitting) onCancel(); }}>
      <DialogContent className="sm:rounded-3xl max-w-lg">
        <DialogHeader>
          <DialogTitle className="text-text-primary">{t.pages.shifts.move.title}</DialogTitle>
          <DialogDescription className="text-text-muted">
            {t.pages.shifts.move.description}
          </DialogDescription>
        </DialogHeader>
        {isSubmitting && (
          <div className="absolute inset-0 z-50 flex items-center justify-center rounded-3xl bg-surface-primary/80 backdrop-blur-sm">
            <div className="flex flex-col items-center gap-3">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-border-subtle border-t-brand-highlight" />
              <p className="text-sm font-medium text-text-secondary">{t.pages.shifts.move.moving}</p>
            </div>
          </div>
        )}
        <div className="space-y-5 pt-2">
          <div className="flex flex-col items-center gap-5">
            <div className="flex items-center gap-6">
              {isReverseDirection ? (
                <>
                  {toSection}
                  {directionArrow}
                  {fromSection}
                </>
              ) : (
                <>
                  {fromSection}
                  {directionArrow}
                  {toSection}
                </>
              )}
            </div>
          </div>
          {shifts.length > 0 && (
            <div className="space-y-3">
              {multipleShifts && (
                <p className="text-xs font-medium text-text-secondary">
                  {t.pages.shifts.move.selectShiftsToMove}
                </p>
              )}
              <div className={cn(
                "flex flex-col gap-2",
                multipleShifts && "max-h-[156px] overflow-y-auto pr-1 -mr-1"
              )}>
                {shifts.map((shift) => (
                  <ShiftMoveCard
                    key={shift.id}
                    shift={shift}
                    targetDate={targetDate}
                    selected={selectedIds.includes(shift.id)}
                    onToggle={onToggleShift}
                    userSettings={userSettings}
                    presetRules={presetRules}
                  />
                ))}
              </div>
            </div>
          )}
          {error && (
            <p className="text-sm text-error">
              {error}
            </p>
          )}
          {!error && !targetDate && (
            <p className="text-sm text-text-muted">
              {t.pages.shifts.move.selectTargetDate}
            </p>
          )}
          {!error && targetDate && selectedIds.length === 0 && multipleShifts && (
            <p className="text-sm text-text-muted">
              {t.pages.shifts.move.selectAtLeastOne}
            </p>
          )}
        </div>
        <DialogFooter className="pt-4 flex w-full flex-row items-center gap-3">
          <Button
            type="button"
            variant="ghost"
            onClick={onCancel}
            disabled={isSubmitting}
            className="flex-1 h-11 rounded-full border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900"
          >
            {t.pages.shifts.move.cancelButton}
          </Button>
          <Button
            type="button"
            variant="default"
            onClick={onConfirm}
            loading={isSubmitting}
            disabled={isSubmitting || selectedIds.length === 0 || !targetDate}
            className="flex-1 h-11 rounded-full"
          >
            {t.pages.shifts.move.confirmButton}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

type ShiftsViewProps = {
  shifts: ShiftWithComputations[];
  defaultView?: string;
  userSettings: UserSettings;
  presetRules: SupplementRule[];
};

export function ShiftsView({ shifts: initialShifts, defaultView = "calendar", userSettings, presetRules }: ShiftsViewProps) {
  const { t, locale } = useTranslations();
  const {
    errorSelectOne,
    errorPartial,
    errorComplete,
    errorUnexpected,
  } = t.pages.shifts.move;
  const router = useRouter();
  const searchParams = useSearchParams();
  const { navigate } = useNavigationFeedback();
  const [pending, startTransition] = useTransition();
  const [moving, startMoveTransition] = useTransition();
  const { selectedMonth, setSelectedMonth } = useMonth();
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [selectedShift, setSelectedShift] = useState<ShiftWithComputations | null>(null);
  const [selectedDate, setSelectedDate] = useState<ISODate | null>(null);
  const [calendarSelectedShiftId, setCalendarSelectedShiftId] = useState<string | null>(null);
  const [moveModalOpen, setMoveModalOpen] = useState(false);
  const [moveTargetDate, setMoveTargetDate] = useState<ISODate | null>(null);
  const [moveSelection, setMoveSelection] = useState<string[]>([]);
  const [moveError, setMoveError] = useState<string | null>(null);
  const [moveMode, setMoveMode] = useState(false);
  const [openedFromCalendar, setOpenedFromCalendar] = useState(false);
  const [copyMode, setCopyMode] = useState(false);
  const [copying, startCopyTransition] = useTransition();
  const [additionalShifts, setAdditionalShifts] = useState<ShiftWithComputations[]>([]);
  const [loadingMonth, setLoadingMonth] = useState(false);
  const shiftsListRef = useRef<HTMLDivElement>(null);
  const calendarContainerRef = useRef<HTMLDivElement>(null);
  const [deletedShiftIds, setDeletedShiftIds] = useState<Set<string>>(new Set());
  const [newlyAddedDates, setNewlyAddedDates] = useState<Set<string>>(new Set());
  const [movedShifts, setMovedShifts] = useState<Map<string, { newDate: string; newStartTime: string; newEndTime: string }>>(new Map());
  const [copiedShifts, setCopiedShifts] = useState<ShiftWithComputations[]>([]);

  // Track which months have been loaded or are currently loading
  const [loadedMonths, setLoadedMonths] = useState<Set<string>>(new Set());
  const [loadingMonths, setLoadingMonths] = useState<Set<string>>(new Set());

  // Combine initial shifts with any dynamically loaded shifts, filtering out deleted ones
  // and applying optimistic move/copy updates
  const shifts = useMemo(
    () => [...initialShifts, ...additionalShifts, ...copiedShifts]
      .filter(shift => !deletedShiftIds.has(shift.id))
      .map(shift => {
        const moved = movedShifts.get(shift.id);
        if (moved) {
          return {
            ...shift,
            shift_date: moved.newDate,
            start_time: moved.newStartTime,
            end_time: moved.newEndTime,
          };
        }
        return shift;
      }),
    [initialShifts, additionalShifts, deletedShiftIds, movedShifts, copiedShifts]
  );

  const clearSelection = useCallback(() => {
    setSelectedDate(null);
    setCalendarSelectedShiftId(null);
    setMoveSelection([]);
    setMoveModalOpen(false);
    setMoveTargetDate(null);
    setMoveError(null);
    setMoveMode(false);
    setOpenedFromCalendar(false);
    setCopyMode(false);
  }, []);

  // Helper to generate month key for tracking
  const getMonthKey = useCallback((year: number, month: number): string => {
    return `${year}-${String(month).padStart(2, '0')}`;
  }, []);

  // Helper to fetch a month's shifts and update state
  const fetchMonth = useCallback(async (year: number, month: number) => {
    const key = getMonthKey(year, month);

    // Skip if already loaded or currently loading
    if (loadedMonths.has(key) || loadingMonths.has(key)) {
      return;
    }

    // Mark as loading
    setLoadingMonths(prev => new Set(prev).add(key));

    try {
      const response = await fetch(`/api/shifts?year=${year}&month=${month}`);
      const data = await response.json();

      if (data.shifts && Array.isArray(data.shifts)) {
        setAdditionalShifts(prev => {
          // Filter out any duplicates before adding
          const existingIds = new Set([...initialShifts, ...prev].map(s => s.id));
          const newShifts = data.shifts.filter((s: ShiftWithComputations) => !existingIds.has(s.id));
          return [...prev, ...newShifts];
        });

        // Mark as successfully loaded
        setLoadedMonths(prev => new Set(prev).add(key));
      }
    } catch (err) {
      console.error(`Failed to fetch month ${key}:`, err);
    } finally {
      // Remove from loading set
      setLoadingMonths(prev => {
        const next = new Set(prev);
        next.delete(key);
        return next;
      });
    }
  }, [getMonthKey, loadedMonths, loadingMonths, initialShifts]);

  // Manual load button handler (fallback if prefetch didn't trigger)
  const handleLoadMonth = useCallback(() => {
    const selectedYear = selectedMonth.getFullYear();
    const selectedMonthNum = selectedMonth.getMonth() + 1;

    setLoadingMonth(true);
    fetchMonth(selectedYear, selectedMonthNum).finally(() => {
      setLoadingMonth(false);
    });
  }, [selectedMonth, fetchMonth]);
  const shiftsByDate = useMemo(() => {
    const map = new Map<ISODate, ShiftWithComputations[]>();
    for (const shift of shifts) {
      const iso = shift.shift_date as ISODate;
      const existing = map.get(iso);
      if (existing) {
        existing.push(shift);
      } else {
        map.set(iso, [shift]);
      }
    }
    map.forEach((items) => {
      items.sort((a, b) => a.start_time.localeCompare(b.start_time));
    });
    return map;
  }, [shifts]);

  // Initialize loaded months from SSR data on mount
  useEffect(() => {
    const loaded = new Set<string>();
    for (const shift of initialShifts) {
      const [year, month] = shift.shift_date.split('-');
      const key = `${year}-${month}`;
      loaded.add(key);
    }
    setLoadedMonths(loaded);
  }, [initialShifts]);

  // Reset optimistic updates when new data arrives from server (after router.refresh())
  useEffect(() => {
    setDeletedShiftIds(new Set());
    setMovedShifts(new Map());
    setCopiedShifts([]);
  }, [initialShifts]);

  // Proactive prefetch: Load adjacent months (prev, current, next) whenever selectedMonth changes
  useEffect(() => {
    const selectedYear = selectedMonth.getFullYear();
    const selectedMonthNum = selectedMonth.getMonth() + 1;

    // Calculate prev and next months
    const prevDate = new Date(selectedYear, selectedMonthNum - 2, 1);
    const nextDate = new Date(selectedYear, selectedMonthNum, 1);

    const prevYear = prevDate.getFullYear();
    const prevMonthNum = prevDate.getMonth() + 1;
    const nextYear = nextDate.getFullYear();
    const nextMonthNum = nextDate.getMonth() + 1;

    // Prefetch all 3 months in parallel (fetchMonth checks if already loaded)
    Promise.all([
      fetchMonth(selectedYear, selectedMonthNum), // Current
      fetchMonth(prevYear, prevMonthNum),         // Previous
      fetchMonth(nextYear, nextMonthNum),         // Next
    ]);
  }, [selectedMonth, fetchMonth]);

  // Auto-scroll to shifts list if defaultView is "list"
  useEffect(() => {
    if (defaultView === "list" && shiftsListRef.current) {
      const headerHeight = 96; // Height of TopHeader (theme(spacing.24) = 96px)
      const offset = 32; // Additional spacing (theme(spacing.8) = 32px)
      const targetPosition = shiftsListRef.current.offsetTop - headerHeight - offset;

      window.scrollTo({
        top: targetPosition,
        behavior: "instant"
      });
    }
  }, [defaultView]);

  useEffect(() => {
    if (!selectedDate || detailsOpen || moveModalOpen) {
      return;
    }

    function handlePointerDown(event: PointerEvent) {
      const container = calendarContainerRef.current;
      if (!container) return;
      if (container.contains(event.target as Node)) {
        return;
      }
      clearSelection();
    }

    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
  }, [selectedDate, detailsOpen, moveModalOpen, clearSelection]);

  // Confetti celebration for newly added shifts
  useEffect(() => {
    const newDates = searchParams.get('new');
    const newSeries = searchParams.get('newSeries');

    if (newDates || newSeries) {
      let addedDates: string[] = [];

      // Track newly added dates for highlighting
      if (newDates) {
        addedDates = newDates.split(',');
        setNewlyAddedDates(new Set(addedDates));
      } else if (newSeries) {
        // For series, highlight all visible shifts from that series
        const seriesShifts = shifts.filter(s => s.series_id === newSeries);
        addedDates = seriesShifts.map(s => s.shift_date);
        setNewlyAddedDates(new Set(addedDates));
      }

      // Find all dates in the current month
      const currentMonth = selectedMonth.getMonth();
      const currentYear = selectedMonth.getFullYear();
      const datesInCurrentMonth = addedDates.filter(date => {
        const d = new Date(date + 'T00:00:00');
        return d.getMonth() === currentMonth && d.getFullYear() === currentYear;
      });

      // Small delay to let the page render
      const timer = setTimeout(() => {
        if (datesInCurrentMonth.length > 0) {
          // Fire confetti from each newly added shift in the current month
          datesInCurrentMonth.forEach((date, index) => {
            const calendarCell = document.querySelector(
              `[data-day="${date}"]`
            ) as HTMLElement;

            if (calendarCell) {
              // Get position of the calendar cell
              const rect = calendarCell.getBoundingClientRect();
              const x = (rect.left + rect.width / 2) / window.innerWidth;
              const y = (rect.top + rect.height / 2) / window.innerHeight;

              // Stagger the confetti slightly for multiple dates
              setTimeout(() => {
                confetti({
                  particleCount: 80,
                  spread: 60,
                  origin: { x, y },
                  colors: ['#3b82f6', '#8b5cf6', '#ec4899'],
                  startVelocity: 35,
                  ticks: 60
                });
              }, index * 100);
            }
          });
        } else {
          // No dates in current month, use default position
          confetti({
            particleCount: 100,
            spread: 70,
            origin: { y: 0.6 },
            colors: ['#3b82f6', '#8b5cf6', '#ec4899']
          });
        }
      }, 300);

      // Clean up URL and highlighting after celebration
      const cleanTimer = setTimeout(() => {
        const url = new URL(window.location.href);
        url.searchParams.delete('new');
        url.searchParams.delete('newSeries');
        window.history.replaceState({}, '', url.toString());
        setNewlyAddedDates(new Set());
      }, 3000);

      return () => {
        clearTimeout(timer);
        clearTimeout(cleanTimer);
      };
    }
  }, [searchParams, shifts, selectedMonth]);

  const handleMonthChange = useCallback(
    (month: Date) => {
      setSelectedMonth(startOfMonth(month));
    },
    [setSelectedMonth]
  );

  const handleDayClick = useCallback(
    (iso: string, hasShifts: boolean) => {
      const isoDate = iso as ISODate;
      const targetShifts = shiftsByDate.get(isoDate) ?? [];

      if (selectedDate) {
        if (selectedDate === isoDate) {
          // Deselect when clicking the same date again
          clearSelection();
          return;
        }

        // If in copy mode, copy the shifts to the target date
        if (copyMode) {
          const sourceShifts = shiftsByDate.get(selectedDate) ?? [];
          if (sourceShifts.length > 0) {
            const shiftIds = sourceShifts.map((shift) => shift.id);

            // Optimistically add copied shifts to UI
            const optimisticCopies = sourceShifts.map((shift, index) => ({
              ...shift,
              id: `optimistic-copy-${Date.now()}-${index}`, // Temporary ID
              shift_date: isoDate,
            }));
            setCopiedShifts(prev => [...prev, ...optimisticCopies]);
            clearSelection();

            startCopyTransition(async () => {
              try {
                await copyShifts({
                  shiftIds,
                  targetDate: isoDate,
                });
                router.refresh();
              } catch (error) {
                // Revert optimistic updates on error
                setCopiedShifts(prev =>
                  prev.filter(shift => !optimisticCopies.some(opt => opt.id === shift.id))
                );
                // TODO: Add error handling UI
                console.error("Failed to copy shifts", error);
              }
            });
          }
          return;
        }

        if (moveMode) {
          const sourceShifts = shiftsByDate.get(selectedDate) ?? [];
          if (sourceShifts.length > 0) {
            const defaultSelection =
              sourceShifts.length === 1
                ? [sourceShifts[0].id]
                : [];
            setMoveSelection(defaultSelection);
            setMoveTargetDate(isoDate);
            setMoveError(null);
            setMoveModalOpen(true);
            setMoveMode(false);
            return;
          }

          setMoveMode(false);
          clearSelection();
          return;
        }
      }

      if (hasShifts && targetShifts.length > 0) {
        const shiftToRemember =
          (calendarSelectedShiftId &&
            targetShifts.find((shift) => shift.id === calendarSelectedShiftId)) ??
          targetShifts[0];
        if (shiftToRemember) {
          setSelectedDate(isoDate);
          setCalendarSelectedShiftId(shiftToRemember.id);
          setMoveSelection([]);
          setOpenedFromCalendar(false);
          setCopyMode(false);
          setMoveMode(false);
        }
        return;
      }

      if (selectedDate) {
        clearSelection();
        return;
      }

      navigate(`/${locale}/shifts/add?date=${encodeURIComponent(iso)}`);
    },
    [calendarSelectedShiftId, clearSelection, navigate, selectedDate, shiftsByDate, copyMode, router, moveMode, locale]
  );

  const handleOpenDetails = useCallback(() => {
    if (!selectedDate) return;

    const targetShifts = shiftsByDate.get(selectedDate) ?? [];
    if (targetShifts.length > 0) {
      const shiftToOpen =
        (calendarSelectedShiftId &&
          targetShifts.find((shift) => shift.id === calendarSelectedShiftId)) ??
        targetShifts[0];
      if (shiftToOpen) {
        setSelectedShift(shiftToOpen);
        setOpenedFromCalendar(true);
        setDetailsOpen(true);
      }
    }
  }, [selectedDate, shiftsByDate, calendarSelectedShiftId]);

  const handleInitiateMoveMode = useCallback(() => {
    if (!selectedDate) return;
    setMoveMode(true);
    setMoveSelection([]);
    setMoveTargetDate(null);
    setMoveError(null);
    setCopyMode(false);
  }, [selectedDate]);

  const handleCancelMoveMode = useCallback(() => {
    setMoveMode(false);
    setMoveSelection([]);
    setMoveTargetDate(null);
    setMoveError(null);
  }, []);

  const handleInitiateCopy = useCallback(() => {
    if (!selectedDate) return;
    setMoveMode(false);
    setCopyMode(true);
  }, [selectedDate]);

  const handleCancelCopy = useCallback(() => {
    setCopyMode(false);
  }, []);

  const selectedDateShifts = useMemo(
    () => (selectedDate ? shiftsByDate.get(selectedDate) ?? [] : []),
    [selectedDate, shiftsByDate]
  );

  const handleToggleMoveShift = useCallback((shiftId: string) => {
    setMoveSelection((prev) => {
      const isSelected = prev.includes(shiftId);
      // Don't allow deselecting if there's only one shift
      if (isSelected && selectedDateShifts.length === 1) {
        return prev;
      }
      return isSelected
        ? prev.filter((id) => id !== shiftId)
        : [...prev, shiftId];
    });
  }, [selectedDateShifts.length]);

  const handleCancelMove = useCallback(() => {
    setMoveModalOpen(false);
    setMoveTargetDate(null);
    setMoveSelection([]);
    setMoveError(null);
    setMoveMode(false);
  }, []);

  const handleConfirmMove = useCallback(() => {
    if (!selectedDate || !moveTargetDate) {
      return;
    }

    const sourceShifts = shiftsByDate.get(selectedDate) ?? [];
    const shiftsToMove = sourceShifts.filter((shift) =>
      moveSelection.includes(shift.id)
    );

    if (shiftsToMove.length === 0) {
      setMoveError(errorSelectOne);
      return;
    }

    setMoveError(null);

    // Optimistically update the UI immediately
    const optimisticUpdates = new Map(movedShifts);
    shiftsToMove.forEach((shift) => {
      optimisticUpdates.set(shift.id, {
        newDate: moveTargetDate,
        newStartTime: shift.start_time,
        newEndTime: shift.end_time,
      });
    });
    setMovedShifts(optimisticUpdates);
    clearSelection();

    startMoveTransition(async () => {
      try {
        const results = await Promise.allSettled(
          shiftsToMove.map((shift) => {
            // If this is a series shift, use moveSeriesShift action
            if (shift.series_id) {
              return moveSeriesShift({
                seriesId: shift.series_id,
                sourceDate: selectedDate,
                targetDate: moveTargetDate,
                startTime: shift.start_time,
                endTime: shift.end_time,
              });
            }

            // Otherwise, use regular updateShift
            return updateShift({
              id: shift.id,
              shift_date: moveTargetDate,
              start: shift.start_time,
              end: shift.end_time,
            });
          })
        );

        const failed = results.filter((r) => r.status === "rejected");
        const succeeded = results.filter((r) => r.status === "fulfilled");

        if (failed.length > 0) {
          // Revert optimistic updates for failed shifts
          const revertedUpdates = new Map(optimisticUpdates);
          failed.forEach((result, index) => {
            const failedShift = shiftsToMove[index];
            revertedUpdates.delete(failedShift.id);
          });
          setMovedShifts(revertedUpdates);

          if (succeeded.length > 0) {
            // Partial success - show which ones failed
            setMoveError(
              errorPartial
                .replace('{succeeded}', succeeded.length.toString())
                .replace('{total}', shiftsToMove.length.toString())
                .replace('{failed}', failed.length.toString())
            );
            router.refresh(); // Refresh to show partial success
          } else {
            // Complete failure - revert all optimistic updates
            setMovedShifts(movedShifts);
            const firstError = (failed[0] as PromiseRejectedResult).reason;
            const message =
              firstError instanceof Error
                ? firstError.message
                : errorComplete;
            setMoveError(message);
          }
        } else {
          // Complete success - refresh to get server state
          router.refresh();
        }
      } catch (error) {
        // Unexpected error outside Promise.allSettled - revert all optimistic updates
        setMovedShifts(movedShifts);
        const message =
          error instanceof Error ? error.message : errorUnexpected;
        setMoveError(message);
      }
    });
  }, [
    moveSelection,
    moveTargetDate,
    clearSelection,
    router,
    selectedDate,
    shiftsByDate,
    startMoveTransition,
    errorSelectOne,
    errorPartial,
    errorComplete,
    errorUnexpected,
    movedShifts,
  ]);

  const grouped = useMemo(() => {
    return filterAndGroupByWeek(shifts, selectedMonth);
  }, [shifts, selectedMonth]);

  // Check if we have data for the selected month
  const selectedYear = selectedMonth.getFullYear();
  const selectedMonthNum = selectedMonth.getMonth() + 1;
  const targetKey = `${selectedYear}-${String(selectedMonthNum).padStart(2, '0')}`;
  const hasDataForSelectedMonth = shifts.some(s => s.shift_date.startsWith(targetKey));

  const hasAnyShifts = shifts.length > 0;
  const emptyTitle = hasAnyShifts
    ? t.pages.shifts.list.emptyMonthTitle
    : t.pages.shifts.list.emptyTitle;
  const emptyDescription = hasAnyShifts
    ? t.pages.shifts.list.emptyMonthDescription
    : t.pages.shifts.list.emptyDescription;

  return (
    <>
    <div className="flex w-full flex-col">
      <div className="h-[calc(100vh-theme(spacing.24)-theme(spacing.8))] flex items-center justify-center -mt-8">
        <div className="w-full">
          <MonthlyEarningsCalendar
            shifts={shifts}
            month={selectedMonth}
            onMonthChange={handleMonthChange}
            onDayClick={handleDayClick}
            selectedDate={selectedDate}
            containerRef={calendarContainerRef}
            onClearSelection={clearSelection}
            onOpenDetails={handleOpenDetails}
            copyMode={copyMode}
            onInitiateCopy={handleInitiateCopy}
            copying={copying}
            onCancelCopy={handleCancelCopy}
            onInitiateMove={handleInitiateMoveMode}
            moveMode={moveMode}
            moving={moving}
            onCancelMoveMode={handleCancelMoveMode}
            newlyAddedDates={newlyAddedDates}
          />
        </div>
      </div>
      <div ref={shiftsListRef} className="pb-10">
        {grouped.length === 0 ? (
          <Card className="text-center">
            <CardHeader>
              <CardTitle>{emptyTitle}</CardTitle>
              <CardDescription>{emptyDescription}</CardDescription>
              {!hasDataForSelectedMonth && hasAnyShifts && (
                <div className="pt-4">
                  <Button
                    onClick={handleLoadMonth}
                    disabled={loadingMonth}
                    variant="default"
                    className="mx-auto"
                  >
                    {loadingMonth ? t.pages.shifts.list.loading : t.pages.shifts.list.loadMonth.replace('{month}', selectedMonth.toLocaleDateString('nb-NO', { month: 'long', year: 'numeric' }))}
                  </Button>
                </div>
              )}
            </CardHeader>
          </Card>
        ) : (
          <div className="flex flex-col gap-8">
            {grouped.map((group) => (
              <section key={group.id} className="space-y-4">
                <Card className="rounded-card border-0 bg-surface-primary/50 backdrop-blur">
                  <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3">
                    <div className="flex items-center gap-2 font-medium text-text-primary">
                      <span>{t.pages.shifts.list.weekLabel} {group.label}</span>
                      <svg
                        aria-hidden="true"
                        className="h-4 w-4 text-text-muted"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="1.5"
                      >
                        <path d="m6 9 6 6 6-6" />
                      </svg>
                    </div>
                    <span className="font-semibold text-text-primary">
                      {formatWeekTotal(group.totalGross)}
                    </span>
                  </CardHeader>
                </Card>
                <div className="space-y-4">
                  {group.shifts.map((shift) => (
                    <ShiftCard
                      key={shift.id}
                      shift={shift}
                      onClick={() => {
                        clearSelection();
                        setSelectedShift(shift);
                        setDetailsOpen(true);
                      }}
                    />
                  ))}
                </div>
              </section>
            ))}
          </div>
        )}
      </div>
    </div>
    <MoveShiftModal
      open={moveModalOpen}
      sourceDate={selectedDate}
      targetDate={moveTargetDate}
      shifts={selectedDateShifts}
      selectedIds={moveSelection}
      onToggleShift={handleToggleMoveShift}
      onConfirm={handleConfirmMove}
      onCancel={handleCancelMove}
      isSubmitting={moving}
      error={moveError}
      userSettings={userSettings}
      presetRules={presetRules}
      locale={locale}
      t={t}
    />
    <ShiftDetails
      isOpen={detailsOpen}
      shift={selectedShift}
      onClose={() => {
        setDetailsOpen(false);
        setSelectedShift(null);
        if (openedFromCalendar) {
          clearSelection();
        }
      }}
      isDeleting={pending}
      onDelete={(id) => {
        // Optimistically remove the shift from UI immediately
        setDeletedShiftIds(prev => new Set(prev).add(id));
        setDetailsOpen(false);
        setSelectedShift(null);
        clearSelection();

        startTransition(async () => {
          try {
            await deleteShift(id);
            router.refresh();
          } catch (error) {
            // Revert optimistic update on error
            setDeletedShiftIds(prev => {
              const next = new Set(prev);
              next.delete(id);
              return next;
            });
            // TODO: Add error state to ShiftDetails component and display user-friendly error
            // For now, log the error for debugging
            console.error("Failed to delete shift", error);
          }
        });
      }}
      existingShifts={shifts.map(s => ({ shift_date: s.shift_date, start_time: s.start_time, end_time: s.end_time }))}
      userSettings={userSettings}
      presetRules={presetRules}
    />
    </>
  );
}
