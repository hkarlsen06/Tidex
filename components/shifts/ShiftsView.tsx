"use client";

import { useMemo, useState, useCallback, useTransition, useRef, useEffect, Fragment } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import dynamic from "next/dynamic";

import ShiftCard from "@/components/app/ShiftCard";
import ShiftMoveCard from "./ShiftMoveCard";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/app/Card";
import { CalendarSkeleton } from "@/components/app/skeletons";
import { Button } from "@/components/app/Button";
import { ShiftWithComputations, UserSettings, SupplementRule, computeShift } from "@/lib/payroll";
import ShiftDetails from "@/components/shifts/ShiftDetails";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";
import { updateShift } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { copyShifts } from "@/app/[locale]/(app)/shifts/_actions/copyShifts";
import { moveRecurringShift } from "@/app/[locale]/(app)/shifts/_actions/moveRecurringShift";
import { useNavigationFeedback } from "@/components/app/navigation-feedback";
import { useMonth } from "@/components/app/MonthContext";
import { queueMutation, isOfflineQueueSupported } from "@/lib/pwa/offline-queue";
import type { ISODate } from "@/components/app/calendar-types";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from "@/components/app/Dialog";
import { ArrowRight, ArrowLeft, X, CloudOff } from "lucide-react";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";
import type { Locale } from "@/lib/i18n/config";
import { formatInteger } from "@/lib/formatters";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";
import { getDateFormatter } from "@/lib/i18n/locale";
import { useOnlineStatus } from "@/lib/hooks/useOnlineStatus";
import { useCountdown } from "@/lib/hooks/useCountdown";
import { TodayPlaceholderCard } from "./TodayPlaceholderCard";
import { ScrollablePageWrapper } from "@/components/app/ScrollablePageWrapper";

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
      ? "border-brand-gradient-mid bg-brand-gradient-mid/10"
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
    <ArrowLeft className="h-8 w-8 text-brand-highlight" aria-hidden="true" />
  ) : (
    <ArrowRight className="h-8 w-8 text-brand-highlight" aria-hidden="true" />
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
          <div className="absolute inset-0 z-50 flex items-center justify-center rounded-3xl bg-surface-primary/80 backdrop-blur-xs">
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
  /** When true, hides add button and disables edit/delete/copy/move actions (for shared shifts view) */
  readOnly?: boolean;
  /** Owner name displayed when viewing shared shifts */
  ownerName?: string;
};

export function ShiftsView({ shifts: initialShifts, defaultView = "calendar", userSettings, presetRules, readOnly = false, ownerName }: ShiftsViewProps) {
  const { t, locale } = useTranslations();
  const formatCurrency = useFormatCurrency();
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
  const isOffline = useOnlineStatus();
  const [additionalShifts, setAdditionalShifts] = useState<ShiftWithComputations[]>([]);
  const shiftsListRef = useRef<HTMLDivElement>(null);
  const todayRef = useRef<HTMLDivElement>(null);
  const calendarContainerRef = useRef<HTMLDivElement>(null);
  const [deletedShiftIds, setDeletedShiftIds] = useState<Set<string>>(new Set());
  const [newlyAddedDates, setNewlyAddedDates] = useState<Set<string>>(new Set());
  const [movedShifts, setMovedShifts] = useState<Map<string, { newDate: string; newStartTime: string; newEndTime: string }>>(new Map());
  const hasTriggeredConfetti = useRef<Set<string>>(new Set());
  const [copiedShifts, setCopiedShifts] = useState<ShiftWithComputations[]>([]);
  const [shiftOverrides, setShiftOverrides] = useState<Map<string, ShiftWithComputations>>(new Map());

  // Track which months have been loaded or are currently loading
  const [loadedMonths, setLoadedMonths] = useState<Set<string>>(new Set());
  const [loadingMonths, setLoadingMonths] = useState<Set<string>>(new Set());
  // Cache buster timestamp to force fresh fetches after server mutations
  const [cacheBuster, setCacheBuster] = useState<number>(Date.now());
  // Use ref to track in-flight requests to prevent race conditions
  const inflightRequests = useRef<Set<string>>(new Set());

  // Combine initial shifts with any dynamically loaded shifts, filtering out deleted ones
  // and applying optimistic move/copy updates
  const shifts = useMemo(
    () => [...initialShifts, ...additionalShifts, ...copiedShifts]
      .filter(shift => !deletedShiftIds.has(shift.id))
      .map(shift => {
        // Apply locally fetched overrides (e.g., after saving custom supplements)
        const overridden = shiftOverrides.get(shift.id);
        const baseShift = overridden ? { ...shift, ...overridden } : shift;

        const moved = movedShifts.get(baseShift.id);
        if (moved) {
          return {
            ...baseShift,
            shift_date: moved.newDate,
            start_time: moved.newStartTime,
            end_time: moved.newEndTime,
          };
        }
        return baseShift;
      }),
    [initialShifts, additionalShifts, deletedShiftIds, movedShifts, copiedShifts, shiftOverrides]
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

    // Skip if already loaded, currently loading (state), or in-flight (ref)
    if (loadedMonths.has(key) || loadingMonths.has(key) || inflightRequests.current.has(key)) {
      return;
    }

    // Mark as in-flight immediately (synchronous, prevents race conditions)
    inflightRequests.current.add(key);
    // Mark as loading in state (for UI feedback)
    setLoadingMonths(prev => new Set(prev).add(key));

    try {
      const response = await fetch(`/api/shifts?year=${year}&month=${month}&_=${cacheBuster}`);
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
      // Remove from both tracking mechanisms
      inflightRequests.current.delete(key);
      setLoadingMonths(prev => {
        const next = new Set(prev);
        next.delete(key);
        return next;
      });
    }
  }, [getMonthKey, loadedMonths, loadingMonths, initialShifts, cacheBuster]);

  // Fetch a single shift (by month) to refresh computed data after local updates
  const refreshShiftFromServer = useCallback(async (shiftId: string, shiftDate: string) => {
    const [yearStr, monthStr] = shiftDate.split("-");
    const year = Number(yearStr);
    const month = Number(monthStr);

    if (!year || !month) {
      return;
    }

    try {
      const response = await fetch(`/api/shifts?year=${year}&month=${month}&_=${cacheBuster}`);
      if (!response.ok) return;

      const data = await response.json();
      const freshShift = Array.isArray(data?.shifts)
        ? (data.shifts as ShiftWithComputations[]).find((s) => s.id === shiftId)
        : null;

      if (freshShift) {
        setShiftOverrides((prev) => {
          const next = new Map(prev);
          next.set(freshShift.id, freshShift);
          return next;
        });
        setSelectedShift((prev) => (prev?.id === shiftId ? freshShift : prev));
      }
    } catch (err) {
      console.error("Failed to refresh shift after custom supplements save", err);
    }
  }, [cacheBuster]);

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

  // Reset all client-side state when new data arrives from server (after router.refresh())
  // This includes: optimistic updates, client-fetched shifts, and loaded months tracking
  useEffect(() => {
    // Clear optimistic updates
    setDeletedShiftIds(new Set());
    setMovedShifts(new Map());
    setCopiedShifts([]);
    setShiftOverrides(new Map());

    // Clear client-side fetched shifts to force refetch with fresh data
    setAdditionalShifts([]);

    // Recalculate loaded months from fresh SSR data
    const loaded = new Set<string>();
    for (const shift of initialShifts) {
      const [year, month] = shift.shift_date.split('-');
      const key = `${year}-${month}`;
      loaded.add(key);
    }
    setLoadedMonths(loaded);

    // Also mark SSR-loaded months as complete in the ref (prevents race conditions)
    // The ref is synchronous, so prefetch effect will immediately see these months
    inflightRequests.current.clear();
    loaded.forEach(key => inflightRequests.current.add(key));

    // Clear inflight refs after a short delay (allows prefetch to see them first)
    const timer = setTimeout(() => {
      inflightRequests.current.clear();
    }, 0);

    // Update cache buster to force fresh API fetches (bypasses HTTP cache)
    setCacheBuster(Date.now());

    return () => clearTimeout(timer);
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

    // Prefetch in priority order: current first (most likely to be viewed),
    // then previous (used in calculations), then next
    (async () => {
      await fetchMonth(selectedYear, selectedMonthNum); // Current - highest priority
      await fetchMonth(prevYear, prevMonthNum);         // Previous - needed for calculations
      await fetchMonth(nextYear, nextMonthNum);         // Next - lowest priority
    })();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedMonth]);

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

  // Handle queued shift notification
  const [queuedNotification, setQueuedNotification] = useState<{ type: string; count: number } | null>(null);

  useEffect(() => {
    const queued = searchParams.get('queued');
    const count = parseInt(searchParams.get('count') || '1', 10);

    if (queued) {
      setQueuedNotification({ type: queued, count });

      // Clear URL params after showing notification
      const timer = setTimeout(() => {
        const url = new URL(window.location.href);
        url.searchParams.delete('queued');
        url.searchParams.delete('count');
        window.history.replaceState({}, '', url.toString());
      }, 100);

      // Auto-dismiss notification after 5 seconds
      const dismissTimer = setTimeout(() => {
        setQueuedNotification(null);
      }, 5000);

      return () => {
        clearTimeout(timer);
        clearTimeout(dismissTimer);
      };
    }
  }, [searchParams]);

  // Confetti celebration for newly added shifts
  useEffect(() => {
    const newDates = searchParams.get('new');
    const newRecurring = searchParams.get('newRecurring');

    // Always clean up URL params if they exist, regardless of confetti
    if (newDates || newRecurring) {
      // Create unique key for this celebration
      const celebrationKey = `${newDates || ''}-${newRecurring || ''}`;

      // Skip confetti if we already triggered for these params
      const shouldSkipConfetti = hasTriggeredConfetti.current.has(celebrationKey);

      let addedDates: string[] = [];

      // Track newly added dates for highlighting
      if (newDates) {
        addedDates = newDates.split(',');
        setNewlyAddedDates(new Set(addedDates));
      } else if (newRecurring) {
        // For recurring shift, highlight all visible shifts from that recurring pattern
        const recurringShifts = shifts.filter(s => s.recurring_id === newRecurring);
        addedDates = recurringShifts.map(s => s.shift_date);
        setNewlyAddedDates(new Set(addedDates));

        // If no shifts found yet for recurring pattern, wait for them to load
        if (recurringShifts.length === 0 && !shouldSkipConfetti) {
          return;
        }
      }

      // Find all dates in the current month
      const currentMonth = selectedMonth.getMonth();
      const currentYear = selectedMonth.getFullYear();
      const datesInCurrentMonth = addedDates.filter(date => {
        const d = new Date(date + 'T00:00:00');
        return d.getMonth() === currentMonth && d.getFullYear() === currentYear;
      });

      // Small delay to let the page render (only for confetti)
      const timer = !shouldSkipConfetti ? setTimeout(async () => {
        // Mark that we're triggering confetti for these params (do this right before firing)
        hasTriggeredConfetti.current.add(celebrationKey);

        // Dynamically import confetti only when needed (reduces initial bundle by ~2MB)
        const confetti = (await import('canvas-confetti')).default;

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
      }, 300) : undefined;

      // Clean up URL and highlighting after celebration (always runs)
      const cleanTimer = setTimeout(() => {
        const url = new URL(window.location.href);
        url.searchParams.delete('new');
        url.searchParams.delete('newRecurring');
        window.history.replaceState({}, '', url.toString());
        setNewlyAddedDates(new Set());
        // Remove from tracking set after cleanup
        hasTriggeredConfetti.current.delete(celebrationKey);
      }, 3000);

      return () => {
        if (timer) clearTimeout(timer);
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

      // In readOnly mode, don't allow adding new shifts
      if (readOnly) {
        return;
      }

      navigate(`/${locale}/shifts/add?date=${encodeURIComponent(iso)}`);
    },
    [calendarSelectedShiftId, clearSelection, navigate, selectedDate, shiftsByDate, copyMode, router, moveMode, locale, readOnly]
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
    if (!selectedDate || isOffline) return;
    setMoveMode(true);
    setMoveSelection([]);
    setMoveTargetDate(null);
    setMoveError(null);
    setCopyMode(false);
  }, [selectedDate, isOffline]);

  const handleCancelMoveMode = useCallback(() => {
    setMoveMode(false);
    setMoveSelection([]);
    setMoveTargetDate(null);
    setMoveError(null);
  }, []);

  const handleInitiateCopy = useCallback(() => {
    if (!selectedDate || isOffline) return;
    setMoveMode(false);
    setCopyMode(true);
  }, [selectedDate, isOffline]);

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
            // If this is a recurring shift, use moveRecurringShift action
            if (shift.recurring_id) {
              return moveRecurringShift({
                recurringId: shift.recurring_id,
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

  // Check if we're viewing the current month and get today's date
  // Use local date (not UTC) since shift dates represent local dates
  // Recalculated on every render to ensure it stays current (lightweight operation)
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  const todayDate = `${year}-${month}-${day}`;
  const isCurrentMonth = useMemo(() => {
    const now = new Date();
    return selectedMonth.getFullYear() === now.getFullYear() && selectedMonth.getMonth() === now.getMonth();
  }, [selectedMonth]);

  // Find the current active shift or next upcoming shift (only when viewing current month)
  const nextUpcomingShift = useMemo(() => {
    if (!isCurrentMonth) return null;

    const now = new Date();

    // Sort all shifts by date and time
    const sortedShifts = [...shifts].sort((a, b) => {
      const dateCompare = a.shift_date.localeCompare(b.shift_date);
      if (dateCompare !== 0) return dateCompare;
      return a.start_time.localeCompare(b.start_time);
    });

    // Helper to parse shift times, handling cross-midnight
    const parseShiftTimes = (shift: typeof sortedShifts[0]) => {
      const [startH, startM] = shift.start_time.split(':').map(Number);
      const [endH, endM] = shift.end_time.split(':').map(Number);

      const start = new Date(shift.shift_date + 'T00:00:00');
      start.setHours(startH, startM, 0, 0);

      const end = new Date(shift.shift_date + 'T00:00:00');
      end.setHours(endH, endM, 0, 0);

      // Handle cross-midnight: if end <= start, end is next day
      if (end <= start) {
        end.setDate(end.getDate() + 1);
      }

      return { start, end };
    };

    // First, check if there's a currently active shift
    for (const shift of sortedShifts) {
      const { start, end } = parseShiftTimes(shift);
      if (now >= start && now <= end) {
        return shift;
      }
    }

    // No active shift, find first future shift
    for (const shift of sortedShifts) {
      const [hours, minutes] = shift.start_time.split(':').map(Number);
      const shiftDateTime = new Date(shift.shift_date + 'T00:00:00');
      shiftDateTime.setHours(hours, minutes, 0, 0);

      if (shiftDateTime > now) {
        return shift;
      }
    }

    return null;
  }, [shifts, isCurrentMonth]);

  // Live countdown for the next upcoming shift (or current active shift)
  const countdown = useCountdown({
    shiftDate: nextUpcomingShift?.shift_date ?? null,
    shiftTime: nextUpcomingShift?.start_time ?? null,
    endTime: nextUpcomingShift?.end_time ?? null,
    t,
    highPrecision: true,
  });

  // Auto-scroll to today's date on desktop when viewing current month
  useEffect(() => {
    // Only scroll on desktop (lg breakpoint = 1024px)
    const isDesktop = window.matchMedia("(min-width: 1024px)").matches;
    if (!isDesktop || !isCurrentMonth || !todayRef.current || !shiftsListRef.current) {
      return;
    }

    // Use requestAnimationFrame to ensure DOM is fully rendered
    requestAnimationFrame(() => {
      if (!todayRef.current || !shiftsListRef.current) return;

      const container = shiftsListRef.current;
      const todayElement = todayRef.current;

      // Calculate scroll position to center today's element in the container
      const containerHeight = container.clientHeight;
      const elementTop = todayElement.offsetTop;
      const elementHeight = todayElement.offsetHeight;

      // Scroll so today is roughly centered in the visible area
      const scrollTarget = elementTop - (containerHeight / 2) + (elementHeight / 2);

      container.scrollTo({
        top: Math.max(0, scrollTarget),
        behavior: "instant"
      });
    });
  }, [isCurrentMonth, grouped]);

  const hasAnyShifts = shifts.length > 0;
  const emptyTitle = hasAnyShifts
    ? t.pages.shifts.list.emptyMonthTitle
    : t.pages.shifts.list.emptyTitle;
  const emptyDescription = hasAnyShifts
    ? t.pages.shifts.list.emptyMonthDescription
    : t.pages.shifts.list.emptyDescription;

  return (
    <ScrollablePageWrapper routeKey="shifts" applyContainer={false}>
    {/* Queued Shift Notification */}
    {queuedNotification && (
      <div className="fixed top-20 left-1/2 -translate-x-1/2 z-40 animate-in slide-in-from-top-2 fade-in">
        <div className="rounded-lg border border-blue-500/20 bg-blue-500/10 px-4 py-3 shadow-lg backdrop-blur-xs">
          <div className="flex items-center gap-2">
            <CloudOff className="h-4 w-4 text-blue-500" />
            <div className="text-sm">
              <span className="text-blue-500 font-medium">
                {queuedNotification.type === 'create' &&
                  `${queuedNotification.count} ${queuedNotification.count === 1 ? 'shift' : 'shifts'} queued`}
                {queuedNotification.type === 'update' && 'Shift update queued'}
                {queuedNotification.type === 'delete' && 'Shift deletion queued'}
              </span>
              <span className="text-blue-400 text-xs ml-2">
                Will sync when online
              </span>
            </div>
            <button
              onClick={() => setQueuedNotification(null)}
              className="ml-2 text-blue-400 hover:text-blue-500"
              aria-label="Dismiss"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    )}

    {/* Mobile/Tablet: vertical stack. Desktop: side-by-side, break out of parent container */}
    <div className="flex w-full flex-col lg:relative lg:left-1/2 lg:right-1/2 lg:-ml-[50vw] lg:-mr-[50vw] lg:w-screen lg:flex-row lg:gap-0 lg:px-0 lg:items-start lg:pt-6">
      {/* Calendar Section - On mobile: takes full viewport height (minus header/navbar) and centers calendar */}
      <div className="h-[calc(100dvh-3.5rem-5rem-env(safe-area-inset-top)-env(safe-area-inset-bottom))] flex flex-col justify-center px-4 shrink-0 lg:h-auto lg:w-1/2 lg:sticky lg:top-6 lg:justify-start lg:items-center lg:px-0">
        <div className="w-full max-w-md md:max-w-lg lg:max-w-none lg:w-[480px]">
          <MonthlyEarningsCalendar
            shifts={shifts}
            month={selectedMonth}
            onMonthChange={handleMonthChange}
            onDayClick={handleDayClick}
            selectedDate={selectedDate}
            containerRef={calendarContainerRef}
            onClearSelection={clearSelection}
            onOpenDetails={handleOpenDetails}
            copyMode={readOnly ? false : copyMode}
            onInitiateCopy={readOnly ? undefined : handleInitiateCopy}
            copying={copying}
            onCancelCopy={readOnly ? undefined : handleCancelCopy}
            onInitiateMove={readOnly ? undefined : handleInitiateMoveMode}
            moveMode={readOnly ? false : moveMode}
            moving={moving}
            onCancelMoveMode={readOnly ? undefined : handleCancelMoveMode}
            newlyAddedDates={newlyAddedDates}
            isOffline={isOffline}
            taxSettings={{
              enabled: userSettings.tax_deduction_enabled ?? false,
              percentage: Number(userSettings.tax_percentage) || 0,
              halfTaxMonth: userSettings.half_tax_month ?? null,
            }}
            readOnly={readOnly}
          />
        </div>
      </div>

      {/* Shifts List Section - Right half of screen, centered within */}
      <div className="px-4 lg:w-1/2 lg:flex lg:justify-center lg:px-0">
        <div ref={shiftsListRef} className="pb-10 w-full max-w-md md:max-w-lg lg:max-w-lg lg:overflow-y-auto lg:max-h-[calc(100vh-8rem)] lg:px-4">
        {grouped.length === 0 ? (
          <Card className="text-center">
            <CardHeader>
              <CardTitle>{emptyTitle}</CardTitle>
              <CardDescription>{emptyDescription}</CardDescription>
            </CardHeader>
          </Card>
        ) : (
          <div className="flex flex-col gap-12">
            {grouped.map((group, groupIndex) => {
              // Find if today falls within this week's shifts
              const todayIndex = isCurrentMonth
                ? group.shifts.findIndex(shift => shift.shift_date === todayDate)
                : -1;

              // Check if today is before the first shift in the first group (only for very first group)
              const isTodayBeforeFirstShift = isCurrentMonth && groupIndex === 0 && todayIndex === -1
                && group.shifts.length > 0 && todayDate < group.shifts[0].shift_date;

              // Check if today is after the last shift in this week group
              // This happens when we're still in the same week but haven't worked yet
              const lastShiftDate = group.shifts.length > 0 ? group.shifts[group.shifts.length - 1].shift_date : null;
              const nextGroup = grouped[groupIndex + 1];
              const nextGroupFirstDate = nextGroup?.shifts[0]?.shift_date;

              const isTodayAfterLastShift = isCurrentMonth && todayIndex === -1 && lastShiftDate
                && todayDate > lastShiftDate
                && (!nextGroupFirstDate || todayDate < nextGroupFirstDate);

              return (
                <section key={group.id} className="space-y-4">
                  <div className="flex flex-row items-center justify-between bg-transparent">
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
                      {formatCurrency(group.totalGross)}
                    </span>
                  </div>
                  <div className="space-y-4">
                    {isTodayBeforeFirstShift && (
                      <div ref={todayRef}>
                        <TodayPlaceholderCard />
                      </div>
                    )}
                    {group.shifts.map((shift, shiftIndex) => {
                      const isToday = shift.shift_date === todayDate;
                      const showPlaceholderAfter = todayIndex === -1 && shiftIndex < group.shifts.length - 1
                        && shift.shift_date < todayDate && group.shifts[shiftIndex + 1].shift_date > todayDate;
                      const isNextUpcomingShift = nextUpcomingShift?.id === shift.id;

                      return (
                        <Fragment key={shift.id}>
                          <div ref={isCurrentMonth && isToday ? todayRef : undefined}>
                            <div className="flex flex-col gap-2">
                              <ShiftCard
                                shift={shift}
                                isToday={isCurrentMonth && isToday}
                                onClick={() => {
                                  clearSelection();
                                  setSelectedShift(shift);
                                  setDetailsOpen(true);
                                }}
                                progress={isNextUpcomingShift && countdown.isActive ? countdown.progress : undefined}
                              />
                              {isNextUpcomingShift && countdown.text && (
                                <p className="text-xs text-text-muted text-center">{countdown.text}</p>
                              )}
                            </div>
                          </div>
                          {showPlaceholderAfter && (
                            <div ref={todayRef}>
                              <TodayPlaceholderCard />
                            </div>
                          )}
                        </Fragment>
                      );
                    })}
                    {isTodayAfterLastShift && (
                      <div ref={todayRef}>
                        <TodayPlaceholderCard />
                      </div>
                    )}
                  </div>
                </section>
              );
            })}
          </div>
        )}
        </div>
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
      onShiftUpdate={(updatedSupplements) => {
        if (!selectedShift) return;

        // Use existing computed wage periods to preserve the applied base rate locally
        const baseRate = selectedShift.hourly_wage_snapshot
          ?? selectedShift.computed?.wagePeriods?.[0]?.baseRate
          ?? undefined;
        const rulesForCompute = selectedShift.supplement_rules_snapshot?.rules ?? presetRules;

        const shiftForCompute = {
          ...selectedShift,
          custom_supplements: updatedSupplements,
          ...(typeof baseRate === "number" ? { hourly_wage_snapshot: baseRate } : {}),
        };

        // Optimistically recompute so the breakdown updates immediately
        let updatedShift: ShiftWithComputations = shiftForCompute;
        try {
          const recomputed = computeShift(shiftForCompute, userSettings, rulesForCompute);
          updatedShift = { ...shiftForCompute, computed: recomputed };
        } catch (err) {
          console.error("Failed to recompute shift with custom supplements", err);
        }

        setSelectedShift(updatedShift);
        setShiftOverrides((prev) => {
          const next = new Map(prev);
          next.set(updatedShift.id, updatedShift);
          return next;
        });

        // Fetch authoritative computed shift from the server to stay in sync
        refreshShiftFromServer(updatedShift.id, updatedShift.shift_date);
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
            // If offline and queue is supported, queue the mutation
            if (!navigator.onLine && isOfflineQueueSupported()) {
              try {
                // Find the shift to get recurring_id and shift_date if needed
                const shiftToDelete = shifts.find(s => s.id === id);

                await queueMutation({
                  type: 'DELETE',
                  endpoint: `/api/shifts/${id}${
                    shiftToDelete?.recurring_id
                      ? `?recurringId=${shiftToDelete.recurring_id}&shiftDate=${shiftToDelete.shift_date}`
                      : ''
                  }`,
                  method: 'DELETE',
                });

                // Keep optimistic update - shift stays hidden
                // Will refresh when sync completes
                console.log('[Offline] Shift delete queued:', id);
              } catch (queueError) {
                // Revert optimistic update if queue fails
                setDeletedShiftIds(prev => {
                  const next = new Set(prev);
                  next.delete(id);
                  return next;
                });
                console.error("Failed to queue shift deletion", queueError);
              }
            } else {
              // Revert optimistic update on online error
              setDeletedShiftIds(prev => {
                const next = new Set(prev);
                next.delete(id);
                return next;
              });
              console.error("Failed to delete shift", error);
            }
          }
        });
      }}
      existingShifts={shifts.map(s => ({ shift_date: s.shift_date, start_time: s.start_time, end_time: s.end_time }))}
      userSettings={userSettings}
      presetRules={presetRules}
      readOnly={readOnly}
    />
    </ScrollablePageWrapper>
  );
}
