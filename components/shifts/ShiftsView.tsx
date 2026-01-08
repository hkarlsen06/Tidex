"use client";

import React, { useMemo, useState, useCallback, useTransition, useRef, useEffect, Fragment } from "react";
import { useIsDesktop } from "@/lib/hooks/useIsMobile";
import { useRouter, useSearchParams } from "next/navigation";
import dynamic from "next/dynamic";
import { motion, useInView } from "motion/react";

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
import { ShiftWithComputations, UserSettings, SupplementRule, WageSnapshot, computeShift } from "@/lib/payroll";
import ShiftDetails, { type OverlappingShiftInfo } from "@/components/shifts/ShiftDetails";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";
import { deleteShifts } from "@/app/[locale]/(app)/shifts/_actions/deleteShifts";
import { updateShift } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { copyShifts } from "@/app/[locale]/(app)/shifts/_actions/copyShifts";
import { moveRecurringShift } from "@/app/[locale]/(app)/shifts/_actions/moveRecurringShift";
import { createShifts } from "@/app/[locale]/(app)/shifts/add/actions";
import { checkShiftLimit } from "@/app/[locale]/(app)/shifts/add/_checks/checkShiftLimit";
import { useNavigationFeedback } from "@/components/app/navigation-feedback";
import { useMonth } from "@/components/app/MonthContext";
import { queueMutation, isOfflineQueueSupported } from "@/lib/pwa/offline-queue";
import type { ISODate } from "@/components/app/calendar-types";
import { toISODate } from "@/components/app/calendar-utils";
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
import { useHasNativeTabBar } from "@/lib/contexts/NativeTabBarContext";
import type { PayoutTaxSettings } from "@/data-access/shifts";
import { buildExcludedShiftIds } from "@/lib/shifts/conflictExclusion";
import { celebrationHaptic, selectionEndHaptic, selectionHaptic, selectionStartHaptic } from "@/lib/capacitor/haptics";

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

/**
 * Get the applicable wage snapshot for a given date from a list of snapshots.
 * Snapshots must be ordered by from_date DESC (newest first).
 */
function getSnapshotForDate(snapshots: WageSnapshot[], date: string): WageSnapshot | null {
  // Find the first dated snapshot where from_date <= date
  const applicableSnapshot = snapshots.find(
    (s) => s.from_date !== null && s.from_date <= date
  );
  if (applicableSnapshot) return applicableSnapshot;

  // Fall back to baseline snapshot (from_date = null)
  return snapshots.find((s) => s.from_date === null) ?? null;
}

/**
 * Calculate payout date for earnings in a given month.
 * Payout is in the next month on the payroll day.
 */
function calculatePayoutDate(
  earningsYear: number,
  earningsMonth: number, // 1-12
  payrollDay: number
): string {
  // Payout happens in the following month
  let payoutMonth = earningsMonth + 1;
  let payoutYear = earningsYear;
  if (payoutMonth > 12) {
    payoutMonth = 1;
    payoutYear += 1;
  }
  // Clamp payroll day to valid range for the payout month
  const daysInPayoutMonth = new Date(payoutYear, payoutMonth, 0).getDate();
  const clampedDay = Math.min(payrollDay, daysInPayoutMonth);

  return `${payoutYear}-${String(payoutMonth).padStart(2, "0")}-${String(clampedDay).padStart(2, "0")}`;
}

/**
 * Get tax settings for a specific payout date from wage snapshots.
 */
function getTaxSettingsForPayoutDate(
  snapshots: WageSnapshot[],
  payoutDate: string
): PayoutTaxSettings {
  const snapshot = getSnapshotForDate(snapshots, payoutDate);
  if (!snapshot) return null;
  return {
    enabled: snapshot.tax_enabled,
    percentage: snapshot.tax_percentage,
  };
}

// Scroll-triggered animation for shift cards on mobile (slide in from left)
const scrollCardVariants = {
  hidden: { opacity: 0, x: -30 },
  visible: {
    opacity: 1,
    x: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
};

// Desktop entry animation (slide in from top with stagger)
const getDesktopCardVariants = (index: number) => ({
  hidden: { opacity: 0, y: -20 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
      delay: index * 0.03,
    },
  },
});

// Wrapper component that animates cards based on device
// Mobile: scroll-triggered slide in from left
// Desktop: staggered entry animation from top
const ScrollAnimatedCard = React.forwardRef<HTMLDivElement, { children: React.ReactNode; index?: number }>(
  function ScrollAnimatedCard({ children, index = 0 }, forwardedRef) {
    const internalRef = useRef<HTMLDivElement>(null);
    // Use larger top margin to account for navbar (~96px header + buffer)
    // Bottom margin for bottom navbar (~80px + buffer)
    const isInView = useInView(internalRef, { amount: 0.2, margin: "-120px 0px -100px 0px" });
    // useIsDesktop returns undefined during SSR/hydration, then true/false after mount
    const isDesktop = useIsDesktop();

    // Combine refs using a callback that avoids modifying the forwardedRef directly
    const setRefs = useCallback(
      (node: HTMLDivElement | null) => {
        // Set internal ref for useInView
        (internalRef as React.MutableRefObject<HTMLDivElement | null>).current = node;
        // Forward to external ref using React's imperative handle pattern
        if (typeof forwardedRef === 'function') {
          forwardedRef(node);
        } else if (forwardedRef) {
          // For RefObject, we need to use Object.assign to avoid direct mutation lint error
          Object.assign(forwardedRef, { current: node });
        }
      },
      [forwardedRef]
    );

    // During SSR/hydration (isDesktop === undefined), render without animation
    // to prevent layout shift when viewport is detected
    if (isDesktop === undefined) {
      return (
        <div ref={setRefs}>
          {children}
        </div>
      );
    }

    // On desktop, use staggered top-down entry animation
    if (isDesktop) {
      return (
        <motion.div
          ref={setRefs}
          variants={getDesktopCardVariants(index)}
          initial="hidden"
          animate="visible"
        >
          {children}
        </motion.div>
      );
    }

    return (
      <motion.div
        ref={setRefs}
        variants={scrollCardVariants}
        initial="hidden"
        animate={isInView ? "visible" : "hidden"}
      >
        {children}
      </motion.div>
    );
  }
);

// Animated connector line between conflicting shifts
// Receives visibility state as props instead of refs (proper React pattern)
function ConflictConnector({ topInView, bottomInView }: {
  topInView: boolean;
  bottomInView: boolean;
}) {
  // useIsDesktop returns undefined during SSR/hydration, then true/false after mount
  const isDesktop = useIsDesktop();
  // Track the origin to use - updated when only one card is visible
  const [activeOrigin, setActiveOrigin] = useState<"top" | "bottom">("top");
  // Track previous visibility state to detect transitions
  const [prevState, setPrevState] = useState({ topInView: false, bottomInView: false });

  // On desktop: always fully visible
  // On mobile: scale and origin depend on which cards are visible
  const bothVisible = topInView && bottomInView;
  const onlyTopVisible = topInView && !bottomInView;
  const onlyBottomVisible = !topInView && bottomInView;

  // Compute new origin based on current and previous state
  let newOrigin = activeOrigin;
  if (onlyTopVisible) {
    newOrigin = "top";
  } else if (onlyBottomVisible) {
    newOrigin = "bottom";
  } else if (bothVisible) {
    // When both become visible, check what the previous state was
    // If we were in onlyBottomVisible before, keep "bottom" origin (scrolling up)
    // If we were in onlyTopVisible before, keep "top" origin (scrolling down)
    if (prevState.bottomInView && !prevState.topInView) {
      newOrigin = "bottom";
    } else if (prevState.topInView && !prevState.bottomInView) {
      newOrigin = "top";
    }
    // Otherwise keep current activeOrigin
  }

  // Update state if changed (this pattern is React-approved for derived state)
  if (newOrigin !== activeOrigin) {
    setActiveOrigin(newOrigin);
  }
  if (topInView !== prevState.topInView || bottomInView !== prevState.bottomInView) {
    setPrevState({ topInView, bottomInView });
  }

  // Treat undefined (SSR/hydration) as desktop to show connector immediately
  const isDesktopOrHydrating = isDesktop !== false;
  const scaleY = (isDesktopOrHydrating || bothVisible) ? 1 : 0;

  return (
    <motion.div
      className="absolute left-1/2 top-1/2 w-px -translate-x-1/2 bg-orange-400/60 dark:bg-orange-500/50 -z-10"
      style={{ height: 'calc(100% + 1rem)', transformOrigin: activeOrigin }}
      initial={{ scaleY: isDesktopOrHydrating ? 1 : 0 }}
      animate={{ scaleY }}
      transition={{ duration: 0.3, ease: "easeOut" }}
      aria-hidden="true"
    />
  );
}

// Individual shift item - each item owns its own ref and reports visibility
function ShiftItemWithConnector({
  shift,
  shiftIndex,
  shifts,
  conflictConnectorSet,
  conflictingShiftIds,
  excludedFromTotalIds,
  isCurrentMonth,
  todayDate,
  todayIndex,
  todayRef,
  nextUpcomingShift,
  countdown,
  userSettings,
  showEarnings,
  clearSelection,
  setSelectedShift,
  setDetailsOpen,
  onVisibilityChange,
  onSelectionHaptic,
  nextShiftInView,
}: {
  shift: ShiftWithComputations;
  shiftIndex: number;
  shifts: ShiftWithComputations[];
  conflictConnectorSet: Set<string>;
  conflictingShiftIds: Set<string>;
  excludedFromTotalIds: Set<string>;
  isCurrentMonth: boolean;
  todayDate: string;
  todayIndex: number;
  todayRef: React.RefObject<HTMLDivElement | null>;
  nextUpcomingShift: ShiftWithComputations | null;
  countdown: { isActive: boolean; progress?: number; text: string | null };
  userSettings: UserSettings;
  showEarnings: boolean;
  clearSelection: () => void;
  setSelectedShift: (shift: ShiftWithComputations) => void;
  setDetailsOpen: (open: boolean) => void;
  onVisibilityChange: (shiftId: string, inView: boolean) => void;
  onSelectionHaptic: () => void;
  nextShiftInView: boolean;
}) {
  const cardRef = useRef<HTMLDivElement>(null);
  const viewportMargin = "-120px 0px -100px 0px";
  const inView = useInView(cardRef, { amount: 0.2, margin: viewportMargin });

  const isToday = shift.shift_date === todayDate;
  const showPlaceholderAfter = todayIndex === -1 && shiftIndex < shifts.length - 1
    && shift.shift_date < todayDate && shifts[shiftIndex + 1].shift_date > todayDate;
  const isNextUpcomingShift = nextUpcomingShift?.id === shift.id;
  const hasConnector = conflictConnectorSet.has(shift.id);

  // Report visibility changes to parent and trigger haptic on scroll into view
  const wasInViewRef = useRef(false);
  useEffect(() => {
    onVisibilityChange(shift.id, inView);
    // Trigger selection haptic when card scrolls into view (not on initial render)
    if (inView && !wasInViewRef.current) {
      onSelectionHaptic();
    }
    wasInViewRef.current = inView;
  }, [shift.id, inView, onVisibilityChange, onSelectionHaptic]);

  return (
    <Fragment>
      <div className="relative" ref={cardRef}>
        <ScrollAnimatedCard
          ref={isCurrentMonth && isToday ? todayRef : undefined}
          index={shiftIndex}
        >
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
              taxSettings={{
                enabled: shift.tax_enabled ?? false,
                percentage: shift.tax_percentage ?? 0,
                halfTaxMonth: userSettings.half_tax_month ?? null,
              }}
              showEarnings={showEarnings}
              hasConflict={conflictingShiftIds.has(shift.id)}
              excludedFromTotal={excludedFromTotalIds.has(shift.id)}
            />
            {isNextUpcomingShift && countdown.text && (
              <p className="text-xs text-text-muted text-center">{countdown.text}</p>
            )}
          </div>
        </ScrollAnimatedCard>
        {/* Connector line between consecutive conflicting shifts */}
        {hasConnector && (
          <ConflictConnector topInView={inView} bottomInView={nextShiftInView} />
        )}
      </div>
      {showPlaceholderAfter && (
        <div ref={todayRef}>
          <TodayPlaceholderCard />
        </div>
      )}
    </Fragment>
  );
}

// Component that renders a group of shifts with connectors between conflicting ones
function ShiftGroupContent({
  shifts,
  conflictConnectorSet,
  conflictingShiftIds,
  excludedFromTotalIds,
  isCurrentMonth,
  todayDate,
  todayIndex,
  todayRef,
  nextUpcomingShift,
  countdown,
  userSettings,
  showEarnings,
  clearSelection,
  setSelectedShift,
  setDetailsOpen,
}: {
  shifts: ShiftWithComputations[];
  conflictConnectorSet: Set<string>;
  conflictingShiftIds: Set<string>;
  excludedFromTotalIds: Set<string>;
  isCurrentMonth: boolean;
  todayDate: string;
  todayIndex: number;
  todayRef: React.RefObject<HTMLDivElement | null>;
  nextUpcomingShift: ShiftWithComputations | null;
  countdown: { isActive: boolean; progress?: number; text: string | null };
  userSettings: UserSettings;
  showEarnings: boolean;
  clearSelection: () => void;
  setSelectedShift: (shift: ShiftWithComputations) => void;
  setDetailsOpen: (open: boolean) => void;
}) {
  // Track visibility state for each shift - lifted to parent so siblings can access
  const [visibilityMap, setVisibilityMap] = useState<Map<string, boolean>>(() => new Map());
  const selectionSessionRef = useRef<{
    active: boolean;
    endTimeoutId: ReturnType<typeof setTimeout> | null;
  }>({ active: false, endTimeoutId: null });

  const handleVisibilityChange = useCallback((shiftId: string, inView: boolean) => {
    setVisibilityMap(prev => {
      const next = new Map(prev);
      next.set(shiftId, inView);
      return next;
    });
  }, []);

  const handleSelectionHaptic = useCallback(() => {
    if (!selectionSessionRef.current.active) {
      selectionSessionRef.current.active = true;
      selectionStartHaptic();
    }

    selectionHaptic();

    if (selectionSessionRef.current.endTimeoutId) {
      clearTimeout(selectionSessionRef.current.endTimeoutId);
    }

    selectionSessionRef.current.endTimeoutId = setTimeout(() => {
      selectionSessionRef.current.active = false;
      selectionSessionRef.current.endTimeoutId = null;
      selectionEndHaptic();
    }, 150);
  }, []);

  useEffect(() => {
    const session = selectionSessionRef.current;
    return () => {
      if (session.endTimeoutId) {
        clearTimeout(session.endTimeoutId);
      }
      if (session.active) {
        session.active = false;
        selectionEndHaptic();
      }
    };
  }, []);

  return (
    <>
      {shifts.map((shift, shiftIndex) => {
        const nextShift = shifts[shiftIndex + 1];
        const nextShiftInView = nextShift ? (visibilityMap.get(nextShift.id) ?? false) : false;

        return (
          <ShiftItemWithConnector
            key={shift.id}
            shift={shift}
            shiftIndex={shiftIndex}
            shifts={shifts}
            conflictConnectorSet={conflictConnectorSet}
            conflictingShiftIds={conflictingShiftIds}
            excludedFromTotalIds={excludedFromTotalIds}
            isCurrentMonth={isCurrentMonth}
            todayDate={todayDate}
            todayIndex={todayIndex}
            todayRef={todayRef}
            nextUpcomingShift={nextUpcomingShift}
            countdown={countdown}
            userSettings={userSettings}
            showEarnings={showEarnings}
            clearSelection={clearSelection}
            setSelectedShift={setSelectedShift}
            setDetailsOpen={setDetailsOpen}
            onVisibilityChange={handleVisibilityChange}
            onSelectionHaptic={handleSelectionHaptic}
            nextShiftInView={nextShiftInView}
          />
        );
      })}
    </>
  );
}

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
// Note: Automatically computes excluded shifts for week totals
function filterAndGroupByWeek(
  shifts: ShiftWithComputations[],
  month: Date
): WeekGroup[] {
  const groups: WeekGroup[] = [];
  const map = new Map<string, WeekGroup>();
  const targetMonth = month.getMonth();
  const targetYear = month.getFullYear();

  // Filter shifts for this month first
  const monthShifts: ShiftWithComputations[] = [];
  for (const shift of shifts) {
    const date = parseISODate(shift.shift_date);
    if (date.getUTCMonth() === targetMonth && date.getUTCFullYear() === targetYear) {
      monthShifts.push(shift);
    }
  }

  // Compute excluded shifts for this month's shifts only
  const excludedFromTotal = buildExcludedShiftIds(monthShifts);

  // Group filtered shifts by week
  for (const shift of monthShifts) {
    const date = parseISODate(shift.shift_date);
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
    // Only add to totalGross if the shift is not excluded (conflicting with higher earnings)
    if (!excludedFromTotal.has(shift.id)) {
      group.totalGross += shift.computed.gross;
    }
  }

  // Sort shifts within each week by date, then by start time, then by end time
  for (const group of groups) {
    group.shifts.sort((a, b) => {
      const dateCompare = a.shift_date.localeCompare(b.shift_date);
      if (dateCompare !== 0) return dateCompare;
      const startCompare = a.start_time.localeCompare(b.start_time);
      if (startCompare !== 0) return startCompare;
      return a.end_time.localeCompare(b.end_time);
    });
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

/**
 * Find shifts on the same date that overlap with the given shift's time range.
 * Returns an array of OverlappingShiftInfo for display in ShiftDetails modal.
 */
function findOverlappingShifts(
  shift: ShiftWithComputations,
  allShiftsOnDate: ShiftWithComputations[]
): OverlappingShiftInfo[] {
  const result: OverlappingShiftInfo[] = [];

  const timeToMinutes = (time: string): number => {
    const parts = time.split(':');
    return parseInt(parts[0]) * 60 + parseInt(parts[1]);
  };

  let startA = timeToMinutes(shift.start_time);
  let endA = timeToMinutes(shift.end_time);
  // Handle cross-midnight: if end <= start, treat end as next day
  if (endA <= startA) endA += 24 * 60;

  for (const other of allShiftsOnDate) {
    if (other.id === shift.id) continue; // Skip the shift itself

    let startB = timeToMinutes(other.start_time);
    let endB = timeToMinutes(other.end_time);
    if (endB <= startB) endB += 24 * 60;

    // Two ranges overlap if: startA < endB && startB < endA
    if (startA < endB && startB < endA) {
      result.push({
        id: other.id,
        start_time: other.start_time.substring(0, 5),
        end_time: other.end_time.substring(0, 5),
      });
    }
  }

  return result;
}

/**
 * Build a set of shift IDs that need a visual connector to the next shift.
 * A connector is shown between two consecutive shifts in a week group when:
 * 1. Both shifts are on the same date
 * 2. Both shifts have conflicts
 *
 * @param weekGroups - The grouped shifts by week (used for rendering order)
 * @param conflictingIds - Set of shift IDs that have conflicts
 * @returns Set of shift IDs that should show a connector after them
 */
function buildConflictConnectorSet(
  weekGroups: WeekGroup[],
  conflictingIds: Set<string>
): Set<string> {
  const result = new Set<string>();

  for (const group of weekGroups) {
    const shifts = group.shifts;
    for (let i = 0; i < shifts.length - 1; i++) {
      const current = shifts[i];
      const next = shifts[i + 1];

      // Only add connector if both shifts are on the same date and both have conflicts
      if (
        current.shift_date === next.shift_date &&
        conflictingIds.has(current.id) &&
        conflictingIds.has(next.id)
      ) {
        result.add(current.id);
      }
    }
  }

  return result;
}

/**
 * Build a set of shift IDs that have overlapping conflicts.
 * A shift has a conflict if it overlaps with any other shift on the same date.
 */
function buildConflictingShiftIds(shifts: ShiftWithComputations[]): Set<string> {
  const result = new Set<string>();
  const shiftsByDate = new Map<ISODate, ShiftWithComputations[]>();

  // Group shifts by date
  for (const shift of shifts) {
    const isoDate = shift.shift_date as ISODate;
    const existing = shiftsByDate.get(isoDate) || [];
    existing.push(shift);
    shiftsByDate.set(isoDate, existing);
  }

  const timeToMinutes = (time: string): number => {
    const parts = time.split(':');
    return parseInt(parts[0]) * 60 + parseInt(parts[1]);
  };

  // Check each date for overlapping shifts
  shiftsByDate.forEach((shiftsOnDate) => {
    if (shiftsOnDate.length < 2) return;

    // Check all pairs of shifts for overlap
    for (let i = 0; i < shiftsOnDate.length; i++) {
      for (let j = i + 1; j < shiftsOnDate.length; j++) {
        const shiftA = shiftsOnDate[i];
        const shiftB = shiftsOnDate[j];

        let startA = timeToMinutes(shiftA.start_time);
        let endA = timeToMinutes(shiftA.end_time);
        let startB = timeToMinutes(shiftB.start_time);
        let endB = timeToMinutes(shiftB.end_time);

        // Handle cross-midnight shifts
        if (endA <= startA) endA += 24 * 60;
        if (endB <= startB) endB += 24 * 60;

        // Two ranges overlap if: startA < endB && startB < endA
        if (startA < endB && startB < endA) {
          result.add(shiftA.id);
          result.add(shiftB.id);
        }
      }
    }
  });

  return result;
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
                multipleShifts && "max-h-39 overflow-y-auto pr-1 -mr-1"
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

/**
 * Month context that can be provided externally to isolate state.
 * Used by sharing page to prevent AnimatePresence conflicts with /shifts route.
 */
type MonthContextOverride = {
  selectedMonth: Date;
  setSelectedMonth: (month: Date) => void;
  goToPreviousMonth: () => void;
  goToNextMonth: () => void;
  direction: 'next' | 'previous' | null;
  isHydrated: boolean;
};

type ShiftsViewProps = {
  shifts: ShiftWithComputations[];
  defaultView?: string;
  userSettings: UserSettings;
  presetRules: SupplementRule[];
  /** When true, hides add button and disables edit/delete/copy/move actions (for shared shifts view) */
  readOnly?: boolean;
  /** Owner name displayed when viewing shared shifts */
  ownerName?: string;
  /** Optional slot for custom header content (e.g., sharing dropdown) */
  headerSlot?: React.ReactNode;
  /** Owner ID for fetching additional shared shifts when readOnly=true */
  sharedOwnerId?: string;
  /** When false, hides earnings-related data in readOnly mode (default: true) */
  showEarnings?: boolean;
  /** Payout month tax settings for calculating after-tax monthly totals */
  payoutTaxSettings?: PayoutTaxSettings;
  /** Owner's wage snapshots for computing payoutTaxSettings per month (sharing view only) */
  wageSnapshots?: WageSnapshot[];
  /** Optional external month context to isolate state from global MonthProvider */
  monthContext?: MonthContextOverride;
  /** User-specific cache key to ensure browser HTTP cache is per-user */
  cacheKey?: string;
  /** Deep link: dates to highlight in calendar (from push notification) */
  highlightDates?: Set<string> | null;
};

export function ShiftsView({ shifts: initialShifts, defaultView = "calendar", userSettings, presetRules, readOnly = false, ownerName: _ownerName, headerSlot, sharedOwnerId, showEarnings = true, payoutTaxSettings, wageSnapshots, monthContext, cacheKey, highlightDates }: ShiftsViewProps) {
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
  // Use external month context if provided (for isolated sharing page state),
  // otherwise fall back to global MonthProvider
  const globalMonthContext = useMonth();
  const { selectedMonth, setSelectedMonth } = monthContext ?? globalMonthContext;
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
  // Multi-selection state
  const [multiSelectedDates, setMultiSelectedDates] = useState<Set<ISODate>>(new Set());
  const [deleting, startDeleteTransition] = useTransition();
  const isOffline = useOnlineStatus();
  const hasNativeTabBar = useHasNativeTabBar();
  const [additionalShifts, setAdditionalShifts] = useState<ShiftWithComputations[]>([]);
  const shiftsListRef = useRef<HTMLDivElement>(null);
  const todayRef = useRef<HTMLDivElement>(null);
  const calendarContainerRef = useRef<HTMLDivElement>(null);
  const [deletedShiftIds, setDeletedShiftIds] = useState<Set<string>>(new Set());
  const [newlyAddedDates, setNewlyAddedDates] = useState<Set<string>>(new Set());
  const [movedShifts, setMovedShifts] = useState<Map<string, { newDate: string; newStartTime: string; newEndTime: string }>>(new Map());
  const hasTriggeredConfetti = useRef<Set<string>>(new Set());
  const pendingSaveRef = useRef<string | null>(null); // Tracks optimistic save in progress
  const [copiedShifts, setCopiedShifts] = useState<ShiftWithComputations[]>([]);
  const [shiftOverrides, setShiftOverrides] = useState<Map<string, ShiftWithComputations>>(new Map());
  const [optimisticShifts, setOptimisticShifts] = useState<ShiftWithComputations[]>([]);
  const [createError, setCreateError] = useState<string | null>(null);
  const [operationError, setOperationError] = useState<string | null>(null); // For move/copy/delete/edit failures
  const calendarSelectionSessionRef = useRef<{
    active: boolean;
    endTimeoutId: ReturnType<typeof setTimeout> | null;
  }>({ active: false, endTimeoutId: null });

  // Track which months have been loaded or are currently loading
  // Using refs to avoid race conditions with effects and cacheComponents
  const loadedMonthsRef = useRef<Set<string>>(new Set());
  const loadingMonthsRef = useRef<Set<string>>(new Set());
  const hasInitializedRef = useRef(false);
  // Track the previous initialShifts reference to detect actual SSR data changes
  const prevInitialShiftsRef = useRef<ShiftWithComputations[]>(initialShifts);
  // Cache buster timestamp to force fresh fetches after server mutations
  const [cacheBuster, setCacheBuster] = useState<number>(Date.now());
  // Use ref to track in-flight requests to prevent race conditions
  const inflightRequests = useRef<Set<string>>(new Set());

  // Initialize loaded months synchronously on first render
  // This must happen before any effects run
  if (!hasInitializedRef.current) {
    hasInitializedRef.current = true;
    // Mark SSR-loaded months from initialShifts
    for (const shift of initialShifts) {
      const [year, month] = shift.shift_date.split('-');
      const key = `${year}-${month}`;
      loadedMonthsRef.current.add(key);
    }
  }
  // Track payout tax settings per month (key: "YYYY-MM")
  const [payoutTaxByMonth, setPayoutTaxByMonth] = useState<Map<string, PayoutTaxSettings>>(() => {
    // Initialize with SSR-provided payout tax settings for the current month
    const initial = new Map<string, PayoutTaxSettings>();
    if (payoutTaxSettings) {
      const now = new Date();
      const key = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      initial.set(key, payoutTaxSettings);
    }
    return initial;
  });

  // Combine initial shifts with any dynamically loaded shifts, filtering out deleted ones
  // and applying optimistic move/copy updates
  // In readOnly mode without sharedOwnerId, only use server-provided initialShifts
  // When sharedOwnerId is present, include additionalShifts for shared shifts navigation
  const includeAdditionalShifts = !readOnly || !!sharedOwnerId;

  // Combine all shift sources, deduplicate by ID, and apply overrides
  // This handles race conditions where the same shift may appear in multiple sources:
  // - initialShifts (SSR data, updated by router.refresh())
  // - additionalShifts (client-fetched for adjacent months)
  // - copiedShifts (optimistic copies)
  // - optimisticShifts (optimistic creates)
  const shifts = useMemo(
    () => {
      const seenIds = new Set<string>();
      const result: ShiftWithComputations[] = [];

      // Process sources in priority order: initialShifts first (most authoritative)
      const allSources = [
        initialShifts,
        includeAdditionalShifts ? additionalShifts : [],
        readOnly ? [] : copiedShifts,
        readOnly ? [] : optimisticShifts,
      ];

      for (const source of allSources) {
        for (const shift of source) {
          // Skip deleted shifts
          if (deletedShiftIds.has(shift.id)) continue;

          // Skip duplicates (first occurrence wins - initialShifts has priority)
          if (seenIds.has(shift.id)) continue;

          // For optimistic shifts, also check if a real shift with matching data exists
          if (shift.id.startsWith('optimistic-')) {
            const hasMatchingReal = result.some(
              real =>
                real.shift_date === shift.shift_date &&
                real.start_time === shift.start_time &&
                real.end_time === shift.end_time
            );
            if (hasMatchingReal) continue;
          }

          seenIds.add(shift.id);

          // Apply locally fetched overrides (e.g., after saving custom supplements)
          const overridden = shiftOverrides.get(shift.id);
          const baseShift = overridden ? { ...shift, ...overridden } : shift;

          // Apply move overrides
          const moved = movedShifts.get(baseShift.id);
          if (moved) {
            result.push({
              ...baseShift,
              shift_date: moved.newDate,
              start_time: moved.newStartTime,
              end_time: moved.newEndTime,
            });
          } else {
            result.push(baseShift);
          }
        }
      }

      return result;
    },
    [initialShifts, additionalShifts, deletedShiftIds, copiedShifts, readOnly, includeAdditionalShifts, optimisticShifts, shiftOverrides, movedShifts]
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
    setMultiSelectedDates(new Set());
  }, []);

  // Clear only multi-selection (keep other state)
  const clearMultiSelection = useCallback(() => {
    setMultiSelectedDates(new Set());
  }, []);

  // Helper to generate month key for tracking
  const getMonthKey = useCallback((year: number, month: number): string => {
    return `${year}-${String(month).padStart(2, '0')}`;
  }, []);

  // Helper to fetch a month's shifts and update state
  // ownerId parameter is explicit to avoid any closure/ref issues
  const fetchMonth = useCallback(async (year: number, month: number, ownerId: string | undefined) => {
    // CRITICAL: If readOnly is true, we MUST use /api/sharing
    // If ownerId is missing in readOnly mode, something is wrong - don't fetch
    if (readOnly) {
      if (!ownerId) {
        console.error('[fetchMonth] ERROR: readOnly=true but ownerId is missing! Aborting.');
        return;
      }
      // Continue - will use /api/sharing
    }

    const key = getMonthKey(year, month);

    // Skip if already loaded, currently loading, or in-flight
    if (loadedMonthsRef.current.has(key) || loadingMonthsRef.current.has(key) || inflightRequests.current.has(key)) {
      return;
    }

    // Mark as in-flight and loading immediately (synchronous, prevents race conditions)
    inflightRequests.current.add(key);
    loadingMonthsRef.current.add(key);

    try {
      // Determine endpoint based on mode
      // readOnly mode ALWAYS uses /api/sharing (we already verified ownerId exists above)
      // Non-readOnly mode uses /api/shifts for own shifts
      // Include cacheKey to ensure browser HTTP cache is per-user
      const url = readOnly
        ? `/api/sharing?ownerId=${ownerId}&year=${year}&month=${month}&_ck=${cacheKey || ''}&_=${cacheBuster}`
        : `/api/shifts?year=${year}&month=${month}&_ck=${cacheKey || ''}&_=${cacheBuster}`;

      const response = await fetch(url);
      const data = await response.json();

      if (data.shifts && Array.isArray(data.shifts)) {
        setAdditionalShifts(prev => {
          // Filter out any duplicates before adding
          const existingIds = new Set([...initialShifts, ...prev].map(s => s.id));
          const newShifts = data.shifts.filter((s: ShiftWithComputations) => !existingIds.has(s.id));
          return [...prev, ...newShifts];
        });

        // Store payout tax settings for this month
        if (data.payoutTaxSettings !== undefined) {
          setPayoutTaxByMonth(prev => new Map(prev).set(key, data.payoutTaxSettings));
        }

        // Mark as successfully loaded
        loadedMonthsRef.current.add(key);
      }
    } catch (err) {
      console.error(`Failed to fetch month ${key}:`, err);
    } finally {
      // Remove from tracking mechanisms
      inflightRequests.current.delete(key);
      loadingMonthsRef.current.delete(key);
    }
  // Note: We intentionally exclude initialShifts from deps - it's only used for deduplication
  // and we don't want to recreate this callback on every SSR data change
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [getMonthKey, cacheBuster, readOnly, cacheKey]);

  // Fetch a single shift (by month) to refresh computed data after local updates
  const refreshShiftFromServer = useCallback(async (shiftId: string, shiftDate: string) => {
    const [yearStr, monthStr] = shiftDate.split("-");
    const year = Number(yearStr);
    const month = Number(monthStr);

    if (!year || !month) {
      return;
    }

    try {
      // Include cacheKey to ensure browser HTTP cache is per-user
      const response = await fetch(`/api/shifts?year=${year}&month=${month}&_ck=${cacheKey || ''}&_=${cacheBuster}`);
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
  }, [cacheBuster, cacheKey]);

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
      items.sort((a, b) => {
        const startCompare = a.start_time.localeCompare(b.start_time);
        if (startCompare !== 0) return startCompare;
        return a.end_time.localeCompare(b.end_time);
      });
    });
    return map;
  }, [shifts]);

  // Build set of shift IDs that have overlapping conflicts
  const conflictingShiftIds = useMemo(
    () => buildConflictingShiftIds(shifts),
    [shifts]
  );

  // Build set of shift IDs that should be excluded from totals (higher-earning conflicting shifts)
  const excludedFromTotalIds = useMemo(
    () => buildExcludedShiftIds(shifts),
    [shifts]
  );

  // Get payout tax settings for the currently selected month
  // When wageSnapshots is provided (shared shifts), compute locally without fetching
  // Otherwise fall back to cached/SSR-provided settings
  const currentPayoutTaxSettings = useMemo(() => {
    const year = selectedMonth.getFullYear();
    const month = selectedMonth.getMonth() + 1; // 1-12

    // If we have wage snapshots, compute tax settings locally (no API fetch needed)
    if (wageSnapshots && wageSnapshots.length > 0) {
      const payrollDay = userSettings.payroll_day ?? 15;
      const payoutDate = calculatePayoutDate(year, month, payrollDay);
      return getTaxSettingsForPayoutDate(wageSnapshots, payoutDate);
    }

    // Fall back to cached or SSR-provided settings
    const key = `${year}-${String(month).padStart(2, '0')}`;
    return payoutTaxByMonth.get(key) ?? payoutTaxSettings ?? null;
  }, [selectedMonth, payoutTaxByMonth, payoutTaxSettings, wageSnapshots, userSettings.payroll_day]);

  // Track in-flight tax settings requests to prevent duplicates
  const taxSettingsInflightRef = useRef<Set<string>>(new Set());

  // Fetch payoutTaxSettings for a specific month when not cached
  // This is called when navigating to months that have shifts loaded from SSR
  // but don't have the correct tax settings (SSR only loads tax for current month)
  // NOTE: When wageSnapshots is provided, tax settings are computed locally so no fetch is needed
  useEffect(() => {
    // Skip fetching entirely if we have wage snapshots - tax settings are computed locally
    if (wageSnapshots && wageSnapshots.length > 0) {
      return;
    }

    const year = selectedMonth.getFullYear();
    const month = selectedMonth.getMonth() + 1;
    const key = getMonthKey(year, month);

    // Skip if we already have tax settings for this month
    if (payoutTaxByMonth.has(key)) {
      return;
    }

    // Skip if already fetching
    if (taxSettingsInflightRef.current.has(key)) {
      return;
    }

    // In readOnly mode, only fetch if we have a sharedOwnerId
    if (readOnly && !sharedOwnerId) {
      return;
    }

    // Mark as in-flight
    taxSettingsInflightRef.current.add(key);

    const fetchTaxSettings = async () => {
      try {
        const url = readOnly
          ? `/api/sharing?ownerId=${sharedOwnerId}&year=${year}&month=${month}&_ck=${cacheKey || ''}&_=${cacheBuster}`
          : `/api/shifts?year=${year}&month=${month}&_ck=${cacheKey || ''}&_=${cacheBuster}`;

        const response = await fetch(url);
        const data = await response.json();

        // Store payout tax settings for this month
        if (data.payoutTaxSettings !== undefined) {
          setPayoutTaxByMonth(prev => new Map(prev).set(key, data.payoutTaxSettings));
        }
      } catch (err) {
        console.error(`Failed to fetch tax settings for ${key}:`, err);
      } finally {
        taxSettingsInflightRef.current.delete(key);
      }
    };

    fetchTaxSettings();
  }, [selectedMonth, payoutTaxByMonth, getMonthKey, readOnly, sharedOwnerId, cacheKey, cacheBuster, wageSnapshots]);

  // Reset all client-side state when new data arrives from server (after router.refresh())
  // This includes: optimistic updates, client-fetched shifts, and loaded months tracking
  // IMPORTANT: Only runs when initialShifts reference actually changes, not on cacheComponents reveal
  useEffect(() => {
    // Skip if this is the same reference (cacheComponents reveal, not actual data change)
    if (prevInitialShiftsRef.current === initialShifts) {
      return;
    }
    prevInitialShiftsRef.current = initialShifts;

    // Clear optimistic updates
    setDeletedShiftIds(new Set());
    setMovedShifts(new Map());
    setCopiedShifts([]);
    setShiftOverrides(new Map());

    // Clear client-side fetched shifts to force refetch with fresh data
    setAdditionalShifts([]);

    // Recalculate loaded months from fresh SSR data
    loadedMonthsRef.current.clear();
    loadingMonthsRef.current.clear();
    inflightRequests.current.clear();
    for (const shift of initialShifts) {
      const [year, month] = shift.shift_date.split('-');
      const key = `${year}-${month}`;
      loadedMonthsRef.current.add(key);
    }

    // Update cache buster to force fresh API fetches (bypasses HTTP cache)
    setCacheBuster(Date.now());
  }, [initialShifts]);

  // Proactive prefetch: Load adjacent months (prev, current, next) whenever selectedMonth changes
  // sharedOwnerId is passed explicitly to fetchMonth to avoid any closure issues
  useEffect(() => {
    // In readOnly mode, only fetch if we have a sharedOwnerId (viewing shared shifts)
    // This prevents fetching the current user's shifts when viewing shared shifts
    if (readOnly && !sharedOwnerId) {
      return;
    }

    const selectedYear = selectedMonth.getFullYear();
    const selectedMonthNum = selectedMonth.getMonth() + 1;

    // Calculate prev and next months
    const prevDate = new Date(selectedYear, selectedMonthNum - 2, 1);
    const nextDate = new Date(selectedYear, selectedMonthNum, 1);

    const prevYear = prevDate.getFullYear();
    const prevMonthNum = prevDate.getMonth() + 1;
    const nextYear = nextDate.getFullYear();
    const nextMonthNum = nextDate.getMonth() + 1;

    // Pass sharedOwnerId explicitly to avoid closure issues
    const ownerId = sharedOwnerId;

    // Prefetch in priority order: current first (most likely to be viewed),
    // then previous (used in calculations), then next
    (async () => {
      await fetchMonth(selectedYear, selectedMonthNum, ownerId); // Current - highest priority
      await fetchMonth(prevYear, prevMonthNum, ownerId);         // Previous - needed for calculations
      await fetchMonth(nextYear, nextMonthNum, ownerId);         // Next - lowest priority
    })();
  }, [selectedMonth, fetchMonth, readOnly, sharedOwnerId]);

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

  // Handle deep link: navigate to highlighted dates' month
  // This runs once when highlightDates is provided (from push notification)
  const highlightHandledRef = useRef(false);
  useEffect(() => {
    // Only run once per mount
    if (highlightHandledRef.current) return;
    if (!highlightDates || highlightDates.size === 0) return;

    // Use the first date to navigate to that month
    const firstDate = [...highlightDates][0];
    const dateParts = firstDate.split('-');
    if (dateParts.length >= 2) {
      const year = parseInt(dateParts[0], 10);
      const month = parseInt(dateParts[1], 10);
      if (!isNaN(year) && !isNaN(month)) {
        const targetMonth = new Date(year, month - 1, 1);
        setSelectedMonth(targetMonth);
        highlightHandledRef.current = true;
      }
    }
  }, [highlightDates, setSelectedMonth]);

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

  // Handle optimistic shifts from add page (instant navigation)
  useEffect(() => {
    const optimisticParam = searchParams.get('optimistic');
    const errorParam = searchParams.get('createError');

    if (errorParam) {
      // Show error and clear optimistic shifts
      setCreateError(decodeURIComponent(errorParam));
      setOptimisticShifts([]);

      // Clear URL param
      const url = new URL(window.location.href);
      url.searchParams.delete('createError');
      window.history.replaceState({}, '', url.toString());

      // Auto-dismiss error after 5 seconds
      const dismissTimer = setTimeout(() => {
        setCreateError(null);
      }, 5000);

      return () => clearTimeout(dismissTimer);
    }

    if (optimisticParam) {
      // Create a unique key for this optimistic save to prevent duplicates
      const saveKey = optimisticParam;

      // Skip if we're already processing this exact save request
      if (pendingSaveRef.current === saveKey) {
        return;
      }

      try {
        const data = JSON.parse(decodeURIComponent(optimisticParam)) as {
          dates: string[];
          start: string;
          end: string;
          _save?: boolean;
          _targetMonth?: string;
          _checkLimit?: boolean;
        };

        // Create optimistic shift objects with computed data
        const newOptimisticShifts: ShiftWithComputations[] = data.dates.map((date, index) => {
          // Compute the shift earnings using the same logic as the preview
          const shiftForCompute = {
            id: `optimistic-${Date.now()}-${index}`,
            user_id: 'optimistic',
            shift_date: date,
            start_time: data.start,
            end_time: data.end,
          };

          let computed;
          try {
            computed = computeShift(shiftForCompute, userSettings, presetRules);
          } catch {
            // Fallback computed values if computation fails
            computed = {
              gross: 0,
              paidHours: 0,
              durationHours: 0,
              wagePeriods: [],
              basePay: 0,
              supplementPay: 0,
            };
          }

          return {
            ...shiftForCompute,
            computed,
            _isOptimistic: true, // Flag to identify optimistic shifts
          } as ShiftWithComputations & { _isOptimistic?: boolean };
        });

        setOptimisticShifts(newOptimisticShifts);

        // Highlight the new dates
        setNewlyAddedDates(new Set(data.dates));

        // Navigate to the month of the first shift
        let targetMonth = selectedMonth;
        if (data.dates.length > 0) {
          const firstDate = new Date(data.dates[0] + 'T00:00:00');
          const firstMonth = new Date(firstDate.getFullYear(), firstDate.getMonth(), 1);
          if (firstMonth.getTime() !== selectedMonth.getTime()) {
            setSelectedMonth(firstMonth);
            targetMonth = firstMonth;
          }
        }

        // Clear URL param (keep the state though)
        const url = new URL(window.location.href);
        url.searchParams.delete('optimistic');
        window.history.replaceState({}, '', url.toString());

        // Fire confetti and haptic immediately for instant feedback
        setTimeout(async () => {
          const confetti = (await import('canvas-confetti')).default;
          celebrationHaptic();
          const currentMonth = targetMonth.getMonth();
          const currentYear = targetMonth.getFullYear();

          data.dates.forEach((date, index) => {
            const d = new Date(date + 'T00:00:00');
            if (d.getMonth() !== currentMonth || d.getFullYear() !== currentYear) return;

            const calendarCell = document.querySelector(`[data-day="${date}"]`) as HTMLElement;
            if (calendarCell) {
              const rect = calendarCell.getBoundingClientRect();
              const x = (rect.left + rect.width / 2) / window.innerWidth;
              const y = (rect.top + rect.height / 2) / window.innerHeight;

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
        }, 150); // Small delay to let the calendar render

        // If _save flag is set, trigger the server action to save the shifts
        if (data._save && !readOnly) {
          // Mark this save as in progress to prevent duplicate calls
          pendingSaveRef.current = saveKey;

          const saveShifts = async () => {
            try {
              // Check limit if needed
              if (data._checkLimit && data._targetMonth) {
                const limitCheck = await checkShiftLimit(data._targetMonth);
                if (!limitCheck.allowed && limitCheck.existingMonths) {
                  // Limit hit - redirect back to add page with error
                  setOptimisticShifts([]);
                  pendingSaveRef.current = null;
                  router.push(`/${locale}/shifts/add?limitError=true&targetMonth=${data._targetMonth}&existingMonths=${limitCheck.existingMonths.join(',')}`);
                  return;
                }
              }

              // Create the shifts
              await createShifts({ dates: data.dates, start: data.start, end: data.end });

              // Clear the pending save ref after successful save
              pendingSaveRef.current = null;

              // Refresh to replace optimistic data with real data from server
              router.refresh();
            } catch (e: unknown) {
              const errorMessage = e instanceof Error ? e.message : 'Failed to save shift';
              // If offline and queue is supported, queue the mutation
              if (!navigator.onLine && isOfflineQueueSupported()) {
                try {
                  await queueMutation({
                    type: 'CREATE',
                    endpoint: '/api/shifts',
                    method: 'POST',
                    body: JSON.stringify({ dates: data.dates, start: data.start, end: data.end }),
                  });
                  // Shift stays visible as optimistic, will sync when online
                  pendingSaveRef.current = null;
                } catch {
                  // Show error and clear optimistic shifts
                  setCreateError(errorMessage);
                  setOptimisticShifts([]);
                  pendingSaveRef.current = null;
                }
              } else {
                // Show error and clear optimistic shifts
                setCreateError(errorMessage);
                setOptimisticShifts([]);
                pendingSaveRef.current = null;
              }
            }
          };

          // Run save in background
          saveShifts();
        }

        // Clear highlighting after delay
        const clearTimer = setTimeout(() => {
          setNewlyAddedDates(new Set());
        }, 3000);

        return () => clearTimeout(clearTimer);
      } catch (e) {
        console.error('Failed to parse optimistic shift data:', e);
        // Clear invalid param
        const url = new URL(window.location.href);
        url.searchParams.delete('optimistic');
        window.history.replaceState({}, '', url.toString());
      }
    }
  }, [searchParams, userSettings, presetRules, selectedMonth, setSelectedMonth, readOnly, router, locale]);

  // Clear optimistic shifts when real data arrives from server (after router.refresh())
  // Note: We don't fire confetti here since it was already fired when optimistic shifts appeared
  useEffect(() => {
    if (optimisticShifts.length === 0) return;

    // Check if real shifts match the optimistic ones (by date + time)
    // This handles the case where server data arrives and replaces optimistic data
    const matchedOptimisticIds = new Set<string>();

    for (const optimistic of optimisticShifts) {
      const matchingReal = initialShifts.find(
        real =>
          real.shift_date === optimistic.shift_date &&
          real.start_time === optimistic.start_time &&
          real.end_time === optimistic.end_time &&
          !real.id.startsWith('optimistic-') // Ensure it's a real shift
      );

      if (matchingReal) {
        matchedOptimisticIds.add(optimistic.id);
      }
    }

    if (matchedOptimisticIds.size > 0) {
      // Real data has arrived for some/all optimistic shifts - silently replace them
      setOptimisticShifts(prev => prev.filter(s => !matchedOptimisticIds.has(s.id)));
    }
  }, [initialShifts, optimisticShifts]);

  // Auto-dismiss operation error after 5 seconds
  useEffect(() => {
    if (!operationError) return;

    const dismissTimer = setTimeout(() => {
      setOperationError(null);
    }, 5000);

    return () => clearTimeout(dismissTimer);
  }, [operationError]);

  const triggerCalendarSelectionHaptic = useCallback(() => {
    if (!calendarSelectionSessionRef.current.active) {
      calendarSelectionSessionRef.current.active = true;
      selectionStartHaptic();
    }

    selectionHaptic();

    if (calendarSelectionSessionRef.current.endTimeoutId) {
      clearTimeout(calendarSelectionSessionRef.current.endTimeoutId);
    }

    calendarSelectionSessionRef.current.endTimeoutId = setTimeout(() => {
      calendarSelectionSessionRef.current.active = false;
      calendarSelectionSessionRef.current.endTimeoutId = null;
      selectionEndHaptic();
    }, 150);
  }, []);

  useEffect(() => {
    const session = calendarSelectionSessionRef.current;
    return () => {
      if (session.endTimeoutId) {
        clearTimeout(session.endTimeoutId);
      }
      if (session.active) {
        session.active = false;
        selectionEndHaptic();
      }
    };
  }, []);

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
        celebrationHaptic();

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
      triggerCalendarSelectionHaptic();
      setSelectedMonth(startOfMonth(month));
    },
    [setSelectedMonth, triggerCalendarSelectionHaptic]
  );

  const handleDayClick = useCallback(
    (iso: string, hasShifts: boolean) => {
      triggerCalendarSelectionHaptic();
      const isoDate = iso as ISODate;
      const targetShifts = shiftsByDate.get(isoDate) ?? [];

      // If in multi-selection mode, toggle the date
      if (multiSelectedDates.size > 0) {
        if (hasShifts && targetShifts.length > 0) {
          // Check if we're deselecting and would have only 1 date left
          if (multiSelectedDates.has(isoDate) && multiSelectedDates.size === 2) {
            // Transition back to single-selection mode with the remaining date
            const remaining = [...multiSelectedDates].find(d => d !== isoDate);
            if (remaining) {
              setSelectedDate(remaining);
              setMultiSelectedDates(new Set());
              // Set the first shift of the remaining date as selected
              const remainingShifts = shiftsByDate.get(remaining) ?? [];
              if (remainingShifts.length > 0) {
                setCalendarSelectedShiftId(remainingShifts[0].id);
              }
              return;
            }
          }
          setMultiSelectedDates(prev => {
            const next = new Set(prev);
            if (next.has(isoDate)) {
              next.delete(isoDate);
            } else {
              next.add(isoDate);
            }
            return next;
          });
        }
        return;
      }

      if (selectedDate) {
        if (selectedDate === isoDate) {
          // Deselect when clicking the same date again
          clearSelection();
          return;
        }

        // If clicking another date with shifts while one is selected, start multi-selection
        // Allow multi-selection in readOnly mode only when showEarnings is true (for viewing aggregate earnings)
        const allowMultiSelect = !copyMode && !moveMode && (!readOnly || showEarnings);
        if (hasShifts && targetShifts.length > 0 && allowMultiSelect) {
          // Start multi-selection with both dates
          setMultiSelectedDates(new Set([selectedDate, isoDate]));
          setSelectedDate(null);
          setCalendarSelectedShiftId(null);
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
                const errorMessage = error instanceof Error ? error.message : errorComplete;
                setOperationError(errorMessage);
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
    [calendarSelectedShiftId, clearSelection, navigate, selectedDate, shiftsByDate, copyMode, router, moveMode, locale, readOnly, multiSelectedDates, errorComplete, showEarnings, triggerCalendarSelectionHaptic]
  );

  const handleSelectDateRange = useCallback(
    (startIso: ISODate, endIso: ISODate) => {
      const allowMultiSelect = !copyMode && !moveMode && (!readOnly || showEarnings);
      if (!allowMultiSelect) return;

      const startDate = new Date(`${startIso}T00:00:00`);
      const endDate = new Date(`${endIso}T00:00:00`);
      const step = startDate <= endDate ? 1 : -1;
      const range: ISODate[] = [];
      const cursor = new Date(startDate);

      while ((step > 0 && cursor <= endDate) || (step < 0 && cursor >= endDate)) {
        range.push(toISODate(cursor) as ISODate);
        cursor.setDate(cursor.getDate() + step);
      }

      const selectable = range.filter((iso) => (shiftsByDate.get(iso)?.length ?? 0) > 0);
      if (selectable.length === 0) return;

      triggerCalendarSelectionHaptic();
      setCopyMode(false);
      setMoveMode(false);
      setMoveSelection([]);
      setOpenedFromCalendar(false);

      const merged = new Set<ISODate>();
      if (selectedDate) merged.add(selectedDate);
      multiSelectedDates.forEach((iso) => merged.add(iso));
      selectable.forEach((iso) => merged.add(iso));

      if (merged.size === 1) {
        const onlyDate = [...merged][0];
        const onlyShifts = shiftsByDate.get(onlyDate) ?? [];
        if (onlyShifts.length > 0) {
          setSelectedDate(onlyDate);
          setCalendarSelectedShiftId(onlyShifts[0].id);
          setMultiSelectedDates(new Set());
        }
        return;
      }

      setSelectedDate(null);
      setCalendarSelectedShiftId(null);
      setMultiSelectedDates(merged);
    },
    [copyMode, moveMode, readOnly, showEarnings, shiftsByDate, triggerCalendarSelectionHaptic, selectedDate, multiSelectedDates]
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

  // Handle bulk deletion of shifts for all multi-selected dates
  const handleDeleteSelected = useCallback(() => {
    if (multiSelectedDates.size === 0 || isOffline) return;

    // Collect all shifts from the selected dates
    const shiftsToDeleteList: ShiftWithComputations[] = [];
    multiSelectedDates.forEach(date => {
      const dateShifts = shiftsByDate.get(date) ?? [];
      shiftsToDeleteList.push(...dateShifts);
    });

    if (shiftsToDeleteList.length === 0) return;

    // Optimistically remove shifts from UI
    const idsToDelete = new Set(shiftsToDeleteList.map(s => s.id));
    setDeletedShiftIds(prev => new Set([...prev, ...idsToDelete]));
    clearMultiSelection();

    startDeleteTransition(async () => {
      try {
        // Bulk delete all shifts in a single server action
        const shiftsPayload = shiftsToDeleteList.map(shift => ({
          shiftId: shift.id,
          recurringId: shift.recurring_id,
          shiftDate: shift.shift_date,
        }));
        await deleteShifts(shiftsPayload);
        router.refresh();
      } catch (error) {
        // Revert optimistic deletions on error
        setDeletedShiftIds(prev => {
          const next = new Set(prev);
          idsToDelete.forEach(id => next.delete(id));
          return next;
        });
        const errorMessage = error instanceof Error ? error.message : errorComplete;
        setOperationError(errorMessage);
        console.error("Failed to delete shifts", error);
      }
    });
  }, [multiSelectedDates, shiftsByDate, isOffline, router, clearMultiSelection, errorComplete]);

  // Handle deletion of shifts for the single selected date (from calendar action bar)
  const handleDeleteSingleDate = useCallback(() => {
    if (!selectedDate || isOffline) return;

    const shiftsToDeleteList = shiftsByDate.get(selectedDate) ?? [];
    if (shiftsToDeleteList.length === 0) return;

    // Optimistically remove shifts from UI
    const idsToDelete = new Set(shiftsToDeleteList.map(s => s.id));
    setDeletedShiftIds(prev => new Set([...prev, ...idsToDelete]));
    clearSelection();

    startDeleteTransition(async () => {
      try {
        // Bulk delete all shifts in a single server action
        const shiftsPayload = shiftsToDeleteList.map(shift => ({
          shiftId: shift.id,
          recurringId: shift.recurring_id,
          shiftDate: shift.shift_date,
        }));
        await deleteShifts(shiftsPayload);
        router.refresh();
      } catch (error) {
        // Revert optimistic deletions on error
        setDeletedShiftIds(prev => {
          const next = new Set(prev);
          idsToDelete.forEach(id => next.delete(id));
          return next;
        });
        const errorMessage = error instanceof Error ? error.message : errorComplete;
        setOperationError(errorMessage);
        console.error("Failed to delete shifts", error);
      }
    });
  }, [selectedDate, shiftsByDate, isOffline, router, clearSelection, errorComplete]);

  const selectedDateShifts = useMemo(
    () => (selectedDate ? shiftsByDate.get(selectedDate) ?? [] : []),
    [selectedDate, shiftsByDate]
  );

  // Compute overlapping shifts for the currently selected shift
  const overlappingShiftsForDetails = useMemo(() => {
    if (!selectedShift) return [];
    const shiftsOnDate = shiftsByDate.get(selectedShift.shift_date as ISODate) ?? [];
    return findOverlappingShifts(selectedShift, shiftsOnDate);
  }, [selectedShift, shiftsByDate]);

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

  // Build set of shift IDs that need a visual connector to the next shift
  const conflictConnectorSet = useMemo(
    () => buildConflictConnectorSet(grouped, conflictingShiftIds),
    [grouped, conflictingShiftIds]
  );

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
      const startCompare = a.start_time.localeCompare(b.start_time);
      if (startCompare !== 0) return startCompare;
      return a.end_time.localeCompare(b.end_time);
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

    {/* Create Error Notification */}
    {createError && (
      <div className="fixed top-20 left-1/2 -translate-x-1/2 z-40 animate-in slide-in-from-top-2 fade-in">
        <div className="rounded-lg border border-error/20 bg-error/10 px-4 py-3 shadow-lg backdrop-blur-xs">
          <div className="flex items-center gap-2">
            <X className="h-4 w-4 text-error" />
            <div className="text-sm">
              <span className="text-error font-medium">
                {createError}
              </span>
            </div>
            <button
              onClick={() => setCreateError(null)}
              className="ml-2 text-error/70 hover:text-error"
              aria-label="Dismiss"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    )}

    {/* Operation Error Notification (for move/copy/delete/edit failures) */}
    {operationError && (
      <div className="fixed top-20 left-1/2 -translate-x-1/2 z-40 animate-in slide-in-from-top-2 fade-in">
        <div className="rounded-lg border border-error/20 bg-error/10 px-4 py-3 shadow-lg backdrop-blur-xs">
          <div className="flex items-center gap-2">
            <X className="h-4 w-4 text-error" />
            <div className="text-sm">
              <span className="text-error font-medium">
                {operationError}
              </span>
            </div>
            <button
              onClick={() => setOperationError(null)}
              className="ml-2 text-error/70 hover:text-error"
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
      {/* Native iOS: no web navbar (5rem), only safe areas. Web: subtract both header (3.5rem) and navbar (5rem) */}
      <div className={cn(
        "flex flex-col justify-center px-4 shrink-0 lg:h-auto lg:w-1/2 lg:sticky lg:top-6 lg:justify-start lg:items-center lg:px-0",
        hasNativeTabBar
          ? "h-[calc(100dvh-3.5rem-env(safe-area-inset-top)-env(safe-area-inset-bottom))]"
          : "h-[calc(100dvh-3.5rem-5rem-env(safe-area-inset-top)-env(safe-area-inset-bottom))]"
      )}>
        <div className="w-full max-w-md md:max-w-lg lg:max-w-none lg:w-120">
          {/* Custom header slot (e.g., sharing dropdown) - constrained to calendar width */}
          {headerSlot && (
            <div className="pb-3">
              {headerSlot}
            </div>
          )}
          <MonthlyEarningsCalendar
            shifts={shifts}
            month={selectedMonth}
            onMonthChange={handleMonthChange}
            onDayClick={handleDayClick}
            onSelectDateRange={handleSelectDateRange}
            selectedDate={selectedDate}
            selectedDates={readOnly && !showEarnings ? undefined : multiSelectedDates}
            onClearMultiSelection={readOnly && !showEarnings ? undefined : clearMultiSelection}
            onDeleteSelected={readOnly ? undefined : handleDeleteSelected}
            onDeleteSingleDate={readOnly ? undefined : handleDeleteSingleDate}
            deleting={deleting}
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
              // Tax settings are now per-shift, default to false for calendar display
              // Individual shifts will use their own tax_enabled/tax_percentage
              enabled: false,
              percentage: 0,
              halfTaxMonth: userSettings.half_tax_month ?? null,
            }}
            payoutTaxSettings={currentPayoutTaxSettings}
            readOnly={readOnly}
            showEarnings={showEarnings}
            calendarId={sharedOwnerId ? `shared-${sharedOwnerId}` : "own-shifts"}
            routePattern={sharedOwnerId ? "/sharing" : "/shifts"}
            monthContext={monthContext}
            highlightDates={highlightDates}
          />
        </div>
      </div>

      {/* Shifts List Section - Right half of screen on desktop, below calendar on mobile */}
      <div className="px-4 lg:flex lg:w-1/2 lg:justify-center lg:px-0">
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
                <section
                  key={group.id}
                  className="space-y-4"
                >
                  <ScrollAnimatedCard index={groupIndex}>
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
                      {showEarnings && (
                        <span className="font-semibold text-text-primary">
                          {formatCurrency(group.totalGross)}
                        </span>
                      )}
                    </div>
                  </ScrollAnimatedCard>
                  <div className="space-y-4">
                    {isTodayBeforeFirstShift && (
                      <div ref={todayRef}>
                        <TodayPlaceholderCard />
                      </div>
                    )}
                    <ShiftGroupContent
                      shifts={group.shifts}
                      conflictConnectorSet={conflictConnectorSet}
                      conflictingShiftIds={conflictingShiftIds}
                      excludedFromTotalIds={excludedFromTotalIds}
                      isCurrentMonth={isCurrentMonth}
                      todayDate={todayDate}
                      todayIndex={todayIndex}
                      todayRef={todayRef}
                      nextUpcomingShift={nextUpcomingShift}
                      countdown={countdown}
                      userSettings={userSettings}
                      showEarnings={showEarnings}
                      clearSelection={clearSelection}
                      setSelectedShift={setSelectedShift}
                      setDetailsOpen={setDetailsOpen}
                    />
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
                const errorMessage = queueError instanceof Error ? queueError.message : errorComplete;
                setOperationError(errorMessage);
                console.error("Failed to queue shift deletion", queueError);
              }
            } else {
              // Revert optimistic update on online error
              setDeletedShiftIds(prev => {
                const next = new Set(prev);
                next.delete(id);
                return next;
              });
              const errorMessage = error instanceof Error ? error.message : errorComplete;
              setOperationError(errorMessage);
              console.error("Failed to delete shift", error);
            }
          }
        });
      }}
      onOptimisticEdit={(shiftId, updates) => {
        // Find the shift to update
        const shiftToUpdate = shifts.find(s => s.id === shiftId);
        if (!shiftToUpdate) return;

        // Use existing computed wage periods to preserve the applied base rate locally
        const baseRate = shiftToUpdate.hourly_wage_snapshot
          ?? shiftToUpdate.computed?.wagePeriods?.[0]?.baseRate
          ?? undefined;
        const rulesForCompute = shiftToUpdate.supplement_rules_snapshot?.rules ?? presetRules;

        const shiftForCompute = {
          ...shiftToUpdate,
          shift_date: updates.shift_date,
          start_time: updates.start_time,
          end_time: updates.end_time,
          ...(typeof baseRate === "number" ? { hourly_wage_snapshot: baseRate } : {}),
        };

        // Optimistically recompute so the UI updates immediately
        let updatedShift: ShiftWithComputations = shiftForCompute;
        try {
          const recomputed = computeShift(shiftForCompute, userSettings, rulesForCompute);
          updatedShift = { ...shiftForCompute, computed: recomputed };
        } catch (err) {
          console.error("Failed to recompute shift after edit", err);
        }

        // Update selected shift if it's the one being edited
        if (selectedShift?.id === shiftId) {
          setSelectedShift(updatedShift);
        }

        // Update shiftOverrides for the list view
        setShiftOverrides((prev) => {
          const next = new Map(prev);
          next.set(updatedShift.id, updatedShift);
          return next;
        });
      }}
      onEditError={(_shiftId, error) => {
        setOperationError(error);
      }}
      onSupplementSaveError={(error) => {
        setOperationError(error);
      }}
      existingShifts={shifts.map(s => ({ shift_date: s.shift_date, start_time: s.start_time, end_time: s.end_time }))}
      userSettings={userSettings}
      presetRules={presetRules}
      readOnly={readOnly}
      showEarnings={showEarnings}
      overlappingShifts={overlappingShiftsForDetails}
      cacheKey={cacheKey}
    />
    </ScrollablePageWrapper>
  );
}
