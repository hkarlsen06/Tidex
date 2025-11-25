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
  diffMs: number;
};

/**
 * Calculates the relative time between now and a given shift date/time with high precision
 * @param shiftDate - ISO date string (YYYY-MM-DD)
 * @param shiftTime - Time string (HH:MM)
 * @param t - Translations object from useTranslations()
 * @param highPrecision - If true, shows seconds when within 1 hour
 * @returns CountdownResult with text, isUpcoming flag, and diffMs
 */
function calculateCountdown(
  shiftDate: string,
  shiftTime: string,
  t: Dictionary,
  highPrecision: boolean = true
): CountdownResult {
  const now = new Date();

  // Parse shift date and time in local timezone
  const [hours, minutes] = shiftTime.split(':').map(Number);
  const shiftDateTime = new Date(shiftDate + 'T00:00:00');
  shiftDateTime.setHours(hours, minutes, 0, 0);

  const diffMs = shiftDateTime.getTime() - now.getTime();
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
        diffMs,
      };
    }

    // Less than 1 hour - show minutes and seconds
    return {
      text: isFuture
        ? interpolate(rt.inMinutesAndSeconds, { minutes: m, seconds: s })
        : interpolate(rt.minutesAndSecondsAgo, { minutes: m, seconds: s }),
      isUpcoming: isFuture,
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
          diffMs,
        };
      }

      // Show full precision with seconds
      return {
        text: isFuture
          ? interpolate(rt.inHoursMinutesAndSeconds, { hours: h, minutes: m, seconds: s })
          : interpolate(rt.hoursMinutesAndSecondsAgo, { hours: h, minutes: m, seconds: s }),
        isUpcoming: isFuture,
        diffMs,
      };
    }

    if (h === 0) {
      return {
        text: isFuture
          ? interpolate(rt.inMinutes, { minutes: m })
          : interpolate(rt.minutesAgo, { minutes: m }),
        isUpcoming: isFuture,
        diffMs,
      };
    }

    if (m === 0) {
      return {
        text: isFuture
          ? interpolate(rt.inHours, { hours: h })
          : interpolate(rt.hoursAgo, { hours: h }),
        isUpcoming: isFuture,
        diffMs,
      };
    }

    return {
      text: isFuture
        ? interpolate(rt.inHoursAndMinutes, { hours: h, minutes: m })
        : interpolate(rt.hoursAndMinutesAgo, { hours: h, minutes: m }),
      isUpcoming: isFuture,
      diffMs,
    };
  }

  // Check if tomorrow
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const isTomorrow =
    shiftDateTime.getDate() === tomorrow.getDate() &&
    shiftDateTime.getMonth() === tomorrow.getMonth() &&
    shiftDateTime.getFullYear() === tomorrow.getFullYear();

  if (isFuture && isTomorrow) {
    return {
      text: rt.tomorrow,
      isUpcoming: true,
      diffMs,
    };
  }

  // Check if yesterday
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday =
    shiftDateTime.getDate() === yesterday.getDate() &&
    shiftDateTime.getMonth() === yesterday.getMonth() &&
    shiftDateTime.getFullYear() === yesterday.getFullYear();

  if (!isFuture && isYesterday) {
    return {
      text: rt.yesterday,
      isUpcoming: false,
      diffMs,
    };
  }

  // For multiple days
  if (totalDays === 1) {
    return {
      text: isFuture ? rt.inOneDay : rt.oneDayAgo,
      isUpcoming: isFuture,
      diffMs,
    };
  }

  return {
    text: isFuture
      ? interpolate(rt.inDays, { days: totalDays })
      : interpolate(rt.daysAgo, { days: totalDays }),
    isUpcoming: isFuture,
    diffMs,
  };
}

type UseCountdownOptions = {
  /** The shift date in ISO format (YYYY-MM-DD) */
  shiftDate: string | null;
  /** The shift start time (HH:MM) */
  shiftTime: string | null;
  /** Translation dictionary */
  t: Dictionary;
  /** Whether to show seconds precision when close (default: true) */
  highPrecision?: boolean;
};

/**
 * Hook that provides a live countdown to a shift's start time
 * Updates every second when within 6 hours, every minute otherwise
 *
 * @returns The countdown text string, null if no shift provided
 */
export function useCountdown({
  shiftDate,
  shiftTime,
  t,
  highPrecision = true,
}: UseCountdownOptions): string | null {
  const [countdownText, setCountdownText] = useState<string | null>(null);

  const updateCountdown = useCallback(() => {
    if (!shiftDate || !shiftTime) {
      setCountdownText(null);
      return null;
    }

    const result = calculateCountdown(shiftDate, shiftTime, t, highPrecision);
    setCountdownText(result.text);
    return result;
  }, [shiftDate, shiftTime, t, highPrecision]);

  useEffect(() => {
    if (!shiftDate || !shiftTime) {
      setCountdownText(null);
      return;
    }

    // Initial calculation
    const result = updateCountdown();
    if (!result) return;

    // Determine update interval based on proximity
    // Within 6 hours: update every second for high precision
    // Otherwise: update every minute
    const sixHoursMs = 6 * 60 * 60 * 1000;
    const isClose = Math.abs(result.diffMs) < sixHoursMs;
    const intervalMs = highPrecision && isClose ? 1000 : 60000;

    const interval = setInterval(() => {
      const newResult = updateCountdown();

      // If shift has started (transition from future to past) or is far away,
      // we might want to adjust the interval
      if (newResult && highPrecision) {
        const nowClose = Math.abs(newResult.diffMs) < sixHoursMs;
        // If proximity changed, clear and let effect re-run
        if (nowClose !== isClose) {
          clearInterval(interval);
        }
      }
    }, intervalMs);

    return () => clearInterval(interval);
  }, [shiftDate, shiftTime, t, highPrecision, updateCountdown]);

  return countdownText;
}
