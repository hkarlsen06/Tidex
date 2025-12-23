"use client";

import { useMemo, useState, useEffect } from "react";
import { cn } from "@/lib/cn";
import { useTranslations } from "@/lib/i18n/client";
import { useCountdown } from "@/lib/hooks/useCountdown";
import { formatDateParts, formatTimeRange } from "@/components/app/ShiftCard";
import type { ShiftWithComputations } from "@/lib/payroll";

type SharedUserShiftPreviewProps = {
  shift: ShiftWithComputations;
  status: "active" | "upcoming" | "past";
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
 * Compact shift preview shown under a sharer's card in the sharing list
 * Shows the shift's date, time range, and relative time (countdown or elapsed)
 * Answers the question "when is my friend working?" at a glance
 */
export function SharedUserShiftPreview({
  shift,
  status: serverStatus,
}: SharedUserShiftPreviewProps) {
  const { t, locale } = useTranslations();

  // Compute status client-side to ensure it's always current
  // The server-computed status may be stale due to caching
  const [currentStatus, setCurrentStatus] = useState(serverStatus);

  useEffect(() => {
    const computeStatus = () => {
      const now = new Date();
      const { start, end } = parseShiftTimes(shift.shift_date, shift.start_time, shift.end_time);

      if (now >= start && now <= end) {
        return "active";
      } else if (now < start) {
        return "upcoming";
      } else {
        return "past";
      }
    };

    // Compute immediately
    setCurrentStatus(computeStatus());

    // Re-compute every second to catch status transitions
    const interval = setInterval(() => {
      setCurrentStatus(computeStatus());
    }, 1000);

    return () => clearInterval(interval);
  }, [shift.shift_date, shift.start_time, shift.end_time]);

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
    <div className="flex items-center gap-3 px-3 py-2 bg-surface-secondary/50 rounded-lg">
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
  );
}
