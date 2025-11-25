"use client";

import { useState, useEffect, useCallback } from "react";
import type { Dictionary } from "@/lib/i18n/dictionaries/no";

// Simple string interpolation helper
function interpolate(str: string, values: Record<string, number>): string {
  return str.replace(/\{(\w+)\}/g, (_, key) => String(values[key] ?? ''));
}

type CountdownResult = {
  text: string;
  isUpcoming: boolean;
  isActive: boolean;
  progress: number; // 0-100, only meaningful when isActive is true
  diffMs: number;
};

/**
 * Parse a shift's start and end times into Date objects, handling cross-midnight shifts
 */
function parseShiftTimes(
  shiftDate: string,
  startTime: string,
  endTime: string
): { startDateTime: Date; endDateTime: Date } {
  const [startHours, startMinutes] = startTime.split(':').map(Number);
  const [endHours, endMinutes] = endTime.split(':').map(Number);

  const startDateTime = new Date(shiftDate + 'T00:00:00');
  startDateTime.setHours(startHours, startMinutes, 0, 0);

  const endDateTime = new Date(shiftDate + 'T00:00:00');
  endDateTime.setHours(endHours, endMinutes, 0, 0);

  // Handle cross-midnight shifts: if end <= start, end is next day
  if (endDateTime <= startDateTime) {
    endDateTime.setDate(endDateTime.getDate() + 1);
  }

  return { startDateTime, endDateTime };
}

/**
 * Calculates the relative time between now and a given shift date/time with high precision
 * Also detects if shift is currently active and calculates progress
 */
function calculateCountdown(
  shiftDate: string,
  startTime: string,
  endTime: string | null,
  t: Dictionary,
  highPrecision: boolean = true
): CountdownResult {
  const now = new Date();

  // Parse shift start time
  const [startHours, startMinutes] = startTime.split(':').map(Number);
  const startDateTime = new Date(shiftDate + 'T00:00:00');
  startDateTime.setHours(startHours, startMinutes, 0, 0);

  // Check if shift is currently active (only if endTime is provided)
  let isActive = false;
  let progress = 0;

  if (endTime) {
    const { startDateTime: start, endDateTime: end } = parseShiftTimes(shiftDate, startTime, endTime);

    if (now >= start && now <= end) {
      isActive = true;
      const totalDuration = end.getTime() - start.getTime();
      const elapsed = now.getTime() - start.getTime();
      progress = Math.min(100, Math.max(0, (elapsed / totalDuration) * 100));
    }
  }

  // If shift is active, return "now" text
  if (isActive) {
    return {
      text: t.common.relativeTime.now,
      isUpcoming: false,
      isActive: true,
      progress,
      diffMs: 0,
    };
  }

  const diffMs = startDateTime.getTime() - now.getTime();
  const isFuture = diffMs > 0;
  const absDiffMs = Math.abs(diffMs);

  const totalSeconds = Math.floor(absDiffMs / 1000);
  const totalMinutes = Math.floor(absDiffMs / (1000 * 60));
  const totalHours = Math.floor(absDiffMs / (1000 * 60 * 60));
  const totalDays = Math.floor(absDiffMs / (1000 * 60 * 60 * 24));

  const rt = t.common.relativeTime;

  // For high precision: show seconds when within 1 hour
  if (highPrecision && totalHours < 1) {
    const m = Math.floor(totalSeconds / 60);
    const s = totalSeconds % 60;

    if (m === 0) {
      // Less than 1 minute - show only seconds
      return {
        text: isFuture
          ? interpolate(rt.inSeconds, { seconds: s })
          : interpolate(rt.secondsAgo, { seconds: s }),
        isUpcoming: isFuture,
        isActive: false,
        progress: 0,
        diffMs,
      };
    }

    // Less than 1 hour - show minutes and seconds
    return {
      text: isFuture
        ? interpolate(rt.inMinutesAndSeconds, { minutes: m, seconds: s })
        : interpolate(rt.minutesAndSecondsAgo, { minutes: m, seconds: s }),
      isUpcoming: isFuture,
      isActive: false,
      progress: 0,
      diffMs,
    };
  }

  // For shifts very close in time (less than 24 hours)
  if (totalHours < 24) {
    const h = Math.floor(totalMinutes / 60);
    const m = totalMinutes % 60;

    // High precision: show hours, minutes and seconds when within a few hours
    if (highPrecision && totalHours < 6) {
      const s = totalSeconds % 60;

      if (h === 0) {
        // Less than 1 hour - already handled above when highPrecision is true
        // This branch handles when highPrecision is false
        return {
          text: isFuture
            ? interpolate(rt.inMinutes, { minutes: m })
            : interpolate(rt.minutesAgo, { minutes: m }),
          isUpcoming: isFuture,
          isActive: false,
          progress: 0,
          diffMs,
        };
      }

      // Show full precision with seconds
      return {
        text: isFuture
          ? interpolate(rt.inHoursMinutesAndSeconds, { hours: h, minutes: m, seconds: s })
          : interpolate(rt.hoursMinutesAndSecondsAgo, { hours: h, minutes: m, seconds: s }),
        isUpcoming: isFuture,
        isActive: false,
        progress: 0,
        diffMs,
      };
    }

    if (h === 0) {
      return {
        text: isFuture
          ? interpolate(rt.inMinutes, { minutes: m })
          : interpolate(rt.minutesAgo, { minutes: m }),
        isUpcoming: isFuture,
        isActive: false,
        progress: 0,
        diffMs,
      };
    }

    if (m === 0) {
      return {
        text: isFuture
          ? interpolate(rt.inHours, { hours: h })
          : interpolate(rt.hoursAgo, { hours: h }),
        isUpcoming: isFuture,
        isActive: false,
        progress: 0,
        diffMs,
      };
    }

    return {
      text: isFuture
        ? interpolate(rt.inHoursAndMinutes, { hours: h, minutes: m })
        : interpolate(rt.hoursAndMinutesAgo, { hours: h, minutes: m }),
      isUpcoming: isFuture,
      isActive: false,
      progress: 0,
      diffMs,
    };
  }

  // Check if tomorrow
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const isTomorrow =
    startDateTime.getDate() === tomorrow.getDate() &&
    startDateTime.getMonth() === tomorrow.getMonth() &&
    startDateTime.getFullYear() === tomorrow.getFullYear();

  if (isFuture && isTomorrow) {
    return {
      text: rt.tomorrow,
      isUpcoming: true,
      isActive: false,
      progress: 0,
      diffMs,
    };
  }

  // Check if yesterday
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday =
    startDateTime.getDate() === yesterday.getDate() &&
    startDateTime.getMonth() === yesterday.getMonth() &&
    startDateTime.getFullYear() === yesterday.getFullYear();

  if (!isFuture && isYesterday) {
    return {
      text: rt.yesterday,
      isUpcoming: false,
      isActive: false,
      progress: 0,
      diffMs,
    };
  }

  // For multiple days
  if (totalDays === 1) {
    return {
      text: isFuture ? rt.inOneDay : rt.oneDayAgo,
      isUpcoming: isFuture,
      isActive: false,
      progress: 0,
      diffMs,
    };
  }

  return {
    text: isFuture
      ? interpolate(rt.inDays, { days: totalDays })
      : interpolate(rt.daysAgo, { days: totalDays }),
    isUpcoming: isFuture,
    isActive: false,
    progress: 0,
    diffMs,
  };
}

type UseCountdownOptions = {
  /** The shift date in ISO format (YYYY-MM-DD) */
  shiftDate: string | null;
  /** The shift start time (HH:MM) */
  shiftTime: string | null;
  /** The shift end time (HH:MM) - optional, needed for active detection and progress */
  endTime?: string | null;
  /** Translation dictionary */
  t: Dictionary;
  /** Whether to show seconds precision when close (default: true) */
  highPrecision?: boolean;
};

type UseCountdownResult = {
  /** The countdown text string */
  text: string | null;
  /** Whether the shift is currently in progress */
  isActive: boolean;
  /** Progress through the shift (0-100), only meaningful when isActive */
  progress: number;
};

/**
 * Hook that provides a live countdown to a shift's start time
 * Updates every second when within 6 hours or during active shift, every minute otherwise
 *
 * @returns Object with text, isActive flag, and progress percentage
 */
export function useCountdown({
  shiftDate,
  shiftTime,
  endTime,
  t,
  highPrecision = true,
}: UseCountdownOptions): UseCountdownResult {
  const [result, setResult] = useState<UseCountdownResult>({
    text: null,
    isActive: false,
    progress: 0,
  });

  const updateCountdown = useCallback(() => {
    if (!shiftDate || !shiftTime) {
      setResult({ text: null, isActive: false, progress: 0 });
      return null;
    }

    const countdownResult = calculateCountdown(
      shiftDate,
      shiftTime,
      endTime ?? null,
      t,
      highPrecision
    );
    setResult({
      text: countdownResult.text,
      isActive: countdownResult.isActive,
      progress: countdownResult.progress,
    });
    return countdownResult;
  }, [shiftDate, shiftTime, endTime, t, highPrecision]);

  useEffect(() => {
    if (!shiftDate || !shiftTime) {
      setResult({ text: null, isActive: false, progress: 0 });
      return;
    }

    // Initial calculation
    const countdownResult = updateCountdown();
    if (!countdownResult) return;

    // Determine update interval based on proximity and active state
    // During active shift or within 6 hours: update every second for high precision
    // Otherwise: update every minute
    const sixHoursMs = 6 * 60 * 60 * 1000;
    const isClose = Math.abs(countdownResult.diffMs) < sixHoursMs;
    const needsFrequentUpdates = countdownResult.isActive || (highPrecision && isClose);
    const intervalMs = needsFrequentUpdates ? 1000 : 60000;

    const interval = setInterval(() => {
      const newResult = updateCountdown();

      // If proximity or active state changed, we might need to adjust the interval
      if (newResult && highPrecision) {
        const nowClose = Math.abs(newResult.diffMs) < sixHoursMs;
        const nowNeedsFrequent = newResult.isActive || nowClose;
        // If frequency need changed, clear and let effect re-run
        if (nowNeedsFrequent !== needsFrequentUpdates) {
          clearInterval(interval);
        }
      }
    }, intervalMs);

    return () => clearInterval(interval);
  }, [shiftDate, shiftTime, endTime, t, highPrecision, updateCountdown]);

  return result;
}
