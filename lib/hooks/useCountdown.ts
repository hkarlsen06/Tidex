"use client";

import { useState, useEffect, useMemo, useRef, useCallback } from "react";
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

  // Count midnight crossings for more intuitive "days" display
  // Users perceive "1 day" as "tomorrow", not "24 hours from now"
  const countMidnightCrossings = (from: Date, to: Date): number => {
    // Normalize to start of day (midnight)
    const fromMidnight = new Date(from);
    fromMidnight.setHours(0, 0, 0, 0);
    const toMidnight = new Date(to);
    toMidnight.setHours(0, 0, 0, 0);

    // Count days between midnights
    const diffDays = Math.round((toMidnight.getTime() - fromMidnight.getTime()) / (1000 * 60 * 60 * 24));
    return Math.abs(diffDays);
  };

  const midnightDays = isFuture
    ? countMidnightCrossings(now, startDateTime)
    : countMidnightCrossings(startDateTime, now);

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

  // For shifts on the same day (0 midnight crossings), show hours/minutes
  if (midnightDays === 0) {
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

  // 1 midnight crossing = tomorrow/yesterday (more user-friendly than "In 1 day")
  if (midnightDays === 1) {
    return {
      text: isFuture ? rt.tomorrow : rt.yesterday,
      isUpcoming: isFuture,
      isActive: false,
      progress: 0,
      diffMs,
    };
  }

  return {
    text: isFuture
      ? interpolate(rt.inDays, { days: midnightDays })
      : interpolate(rt.daysAgo, { days: midnightDays }),
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
  // Track whether we've hydrated to avoid server/client mismatch
  // Using ref since we don't need re-renders when this changes
  const isHydratedRef = useRef(false);

  // Create a stable key from inputs to reset state when they change
  const inputKey = useMemo(
    () => `${shiftDate ?? ""}-${shiftTime ?? ""}-${endTime ?? ""}-${highPrecision}`,
    [shiftDate, shiftTime, endTime, highPrecision]
  );

  // Initial state: no progress, not active (safe for SSR)
  const [result, setResult] = useState<UseCountdownResult>({
    text: null,
    isActive: false,
    progress: 0,
  });
  const [stateKey, setStateKey] = useState(inputKey);

  // Track interval frequency using ref to avoid re-triggering effects
  const intervalMsRef = useRef<number>(60000);
  // We need a state to trigger effect re-subscription when interval changes
  const [intervalTrigger, setIntervalTrigger] = useState(0);

  // Reset state when inputs change - using a key comparison to detect changes
  // and updating state only when the key changes (not on every render)
  if (inputKey !== stateKey) {
    setStateKey(inputKey);
    // Reset to safe state; actual values will be computed in hydration effect
    setResult({ text: null, isActive: false, progress: 0 });
  }

  // Memoized update function that calculates countdown and returns new state
  const computeCountdown = useCallback(() => {
    if (!shiftDate || !shiftTime) {
      return null;
    }

    const countdownResult = calculateCountdown(
      shiftDate,
      shiftTime,
      endTime ?? null,
      t,
      highPrecision
    );

    // Determine new interval
    const sixHoursMs = 6 * 60 * 60 * 1000;
    const isClose = Math.abs(countdownResult.diffMs) < sixHoursMs;
    const needsFrequentUpdates = countdownResult.isActive || (highPrecision && isClose);
    const newIntervalMs = needsFrequentUpdates ? 1000 : 60000;

    return {
      result: {
        text: countdownResult.text,
        isActive: countdownResult.isActive,
        progress: countdownResult.progress,
      },
      intervalMs: newIntervalMs,
    };
  }, [shiftDate, shiftTime, endTime, t, highPrecision]);

  // Combined hydration and input change effect
  // Uses a single effect that handles both mount and subsequent updates
  // The setState call is wrapped in a microtask to avoid the synchronous setState warning
  // while still ensuring the state is updated on the same frame as hydration
  useEffect(() => {
    const computed = computeCountdown();

    if (!computed) {
      isHydratedRef.current = true;
      return;
    }

    // Use queueMicrotask to schedule state update, avoiding the synchronous setState warning
    // while still updating before the next paint
    queueMicrotask(() => {
      setResult(computed.result);

      // Update interval if it changed
      if (computed.intervalMs !== intervalMsRef.current) {
        intervalMsRef.current = computed.intervalMs;
        setIntervalTrigger((prev) => prev + 1);
      }
    });

    isHydratedRef.current = true;
  }, [computeCountdown]);

  // Interval effect: updates countdown periodically (only after hydration)
  useEffect(() => {
    if (!isHydratedRef.current || !shiftDate || !shiftTime) {
      return;
    }

    const interval = setInterval(() => {
      const computed = computeCountdown();
      if (!computed) return;

      setResult(computed.result);

      // Check if we need to change the interval frequency
      if (computed.intervalMs !== intervalMsRef.current) {
        intervalMsRef.current = computed.intervalMs;
        setIntervalTrigger((prev) => prev + 1);
      }
    }, intervalMsRef.current);

    return () => clearInterval(interval);
  }, [shiftDate, shiftTime, computeCountdown, intervalTrigger]);

  return result;
}
