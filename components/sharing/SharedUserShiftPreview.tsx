"use client";

import type React from "react";
import { useMemo, useState, useEffect, useRef } from "react";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";
import { useCountdown } from "@/lib/hooks/useCountdown";
import { formatDateParts, formatTimeRange } from "@/components/app/ShiftCard";
import type { ShiftWithComputations } from "@/lib/payroll";

type SharedUserShiftPreviewProps = {
  shift: ShiftWithComputations;
  /** @deprecated Server status is no longer used - status is computed client-side for accuracy */
  status?: "active" | "upcoming" | "past";
};

/**
 * Parse shift times into Date objects, handling cross-midnight shifts
 */
function parseShiftTimes(
  shiftDate: string,
  startTime: string,
  endTime: string
): { start: Date; end: Date } {
  const [startH, startM] = startTime.split(':').map(Number);
  const [endH, endM] = endTime.split(':').map(Number);

  const start = new Date(shiftDate + 'T00:00:00');
  start.setHours(startH, startM, 0, 0);

  const end = new Date(shiftDate + 'T00:00:00');
  end.setHours(endH, endM, 0, 0);

  // Handle cross-midnight: if end <= start, end is next day
  if (end <= start) {
    end.setDate(end.getDate() + 1);
  }

  return { start, end };
}

/**
 * Compute shift status based on current time
 */
function computeShiftStatus(
  shiftDate: string,
  startTime: string,
  endTime: string
): "active" | "upcoming" | "past" {
  const now = new Date();
  const { start, end } = parseShiftTimes(shiftDate, startTime, endTime);

  if (now >= start && now <= end) {
    return "active";
  } else if (now < start) {
    return "upcoming";
  } else {
    return "past";
  }
}

/**
 * Compute progress percentage through an active shift (0-100)
 */
function computeShiftProgress(
  shiftDate: string,
  startTime: string,
  endTime: string
): number {
  const now = new Date();
  const { start, end } = parseShiftTimes(shiftDate, startTime, endTime);

  const totalDuration = end.getTime() - start.getTime();
  const elapsed = now.getTime() - start.getTime();

  if (totalDuration <= 0) return 0;

  const progress = (elapsed / totalDuration) * 100;
  return Math.max(0, Math.min(100, progress));
}

/**
 * Compact shift preview shown under a sharer's card in the sharing list
 * Shows the shift's date, time range, and relative time (countdown or elapsed)
 * Answers the question "when is my friend working?" at a glance
 */
export function SharedUserShiftPreview({
  shift,
}: SharedUserShiftPreviewProps) {
  const { t, locale } = useTranslations();

  // Compute status and progress client-side to ensure it's always current
  // The server-computed status may be stale due to caching
  // Initialize with "upcoming" and 0 to avoid hydration mismatch (Date.now() differs server/client)
  const [currentStatus, setCurrentStatus] = useState<"active" | "upcoming" | "past">("upcoming");
  const [progress, setProgress] = useState(0);
  // Use ref to track mount state - doesn't need to trigger re-render since updateValues already does
  const hasMountedRef = useRef(false);
  const [hasMounted, setHasMounted] = useState(false);

  useEffect(() => {
    // Mark as mounted using ref (synchronous, no lint warning)
    hasMountedRef.current = true;

    // Compute immediately on mount, then update every second
    const updateValues = () => {
      setCurrentStatus(
        computeShiftStatus(shift.shift_date, shift.start_time, shift.end_time)
      );
      setProgress(
        computeShiftProgress(shift.shift_date, shift.start_time, shift.end_time)
      );
      // Update hasMounted state after first computation to show progress bar
      if (hasMountedRef.current && !hasMounted) {
        setHasMounted(true);
      }
    };

    // Initial computation
    updateValues();

    // Re-compute every second to catch status transitions and update progress
    const interval = setInterval(updateValues, 1000);

    return () => clearInterval(interval);
  }, [shift.shift_date, shift.start_time, shift.end_time, hasMounted]);

  const isActive = currentStatus === "active";

  // Format date parts
  const { dayName, dayNumber, monthName } = useMemo(
    () => formatDateParts(shift.shift_date, locale, t.dateTime.daysShort),
    [shift.shift_date, locale, t.dateTime.daysShort]
  );

  // Countdown for upcoming shifts, or elapsed time for past shifts
  const countdown = useCountdown({
    shiftDate: shift.shift_date,
    shiftTime: shift.start_time,
    endTime: shift.end_time,
    t,
    highPrecision: currentStatus === "active",
  });

  // Determine the status text
  const statusText = useMemo(() => {
    if (currentStatus === "active") {
      return t.common.relativeTime.now;
    }
    return countdown.text;
  }, [currentStatus, countdown.text, t.common.relativeTime.now]);

  return (
    <div className="relative overflow-hidden rounded-lg">
      {/* Progress bar background for active shifts - only show after mount to avoid hydration mismatch */}
      {hasMounted && isActive && (
        <div
          className="absolute inset-0 bg-brand-highlight/10 animate-progress-grow"
          style={{ '--progress-target': `${progress}%` } as React.CSSProperties}
          aria-hidden="true"
        />
      )}
      <div className="flex items-center gap-3 px-3 py-2 bg-surface-secondary/50 relative z-10">
        {/* Shift info */}
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-text-primary truncate">
            {dayName} · {dayNumber}{" "}
            <span className="text-text-muted">{monthName}</span>
          </p>
          <p className="text-xs text-text-muted">
            {formatTimeRange(shift.start_time, shift.end_time)}
          </p>
        </div>

        {/* Relative time badge */}
        <div
          className={cn(
            "shrink-0 text-xs font-medium px-2 py-1 rounded-full",
            currentStatus === "active"
              ? "bg-green-500/10 text-green-600 dark:text-green-400"
              : currentStatus === "upcoming"
                ? "bg-blue-500/10 text-blue-600 dark:text-blue-400"
                : "bg-surface-secondary text-text-muted"
          )}
        >
          {statusText}
        </div>
      </div>
    </div>
  );
}
