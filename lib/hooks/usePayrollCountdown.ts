"use client";

import { useState, useEffect, useMemo, useRef, useCallback } from "react";
import type { Dictionary } from "@/lib/i18n/dictionaries/no";
import type { Locale } from "@/lib/i18n";
import { adjustPayrollDate } from "@/lib/payroll/adjust-payroll-date";
import { countMidnightCrossings } from "@/lib/dates/midnight-crossings";

// Simple string interpolation helper
function interpolate(str: string, values: Record<string, number>): string {
  return str.replace(/\{(\w+)\}/g, (_, key) => String(values[key] ?? ''));
}

type UsePayrollCountdownResult = {
  /** The countdown text string (always has a value, never null) */
  text: string;
  /** Whether the payroll is today */
  isToday: boolean;
  /** Whether the payroll date has passed */
  isPast: boolean;
  /** Progress through the month until payroll (1-100) */
  progress: number;
};

type UsePayrollCountdownOptions = {
  /** The day of the month when payroll is scheduled */
  payrollDay: number;
  /** The selected month to calculate payroll for */
  selectedMonth: Date;
  /** The current locale */
  locale: Locale;
  /** Translation dictionary */
  t: Dictionary;
};

function calculatePayrollCountdown(
  payrollDay: number,
  selectedMonth: Date,
  locale: Locale,
  t: Dictionary
): UsePayrollCountdownResult {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  // Get the adjusted payroll date for the selected month
  const payrollDate = adjustPayrollDate(
    payrollDay,
    selectedMonth.getMonth(),
    selectedMonth.getFullYear(),
    locale
  );
  const payrollDayStart = new Date(
    payrollDate.getFullYear(),
    payrollDate.getMonth(),
    payrollDate.getDate(),
    0, 0, 0, 0
  );

  // Check if this is the current month
  const isCurrentMonth =
    selectedMonth.getFullYear() === now.getFullYear() &&
    selectedMonth.getMonth() === now.getMonth();

  // Determine the state
  const isToday = countMidnightCrossings(today, payrollDayStart) === 0;
  const isPast = today > payrollDayStart;

  // Calculate progress (only for current month, before or on payroll day)
  let progress = 0;
  if (isCurrentMonth && !isPast) {
    const monthStart = new Date(selectedMonth.getFullYear(), selectedMonth.getMonth(), 1, 0, 0, 0, 0);
    const totalDuration = payrollDayStart.getTime() - monthStart.getTime();
    const elapsed = now.getTime() - monthStart.getTime();

    if (totalDuration > 0) {
      progress = (elapsed / totalDuration) * 100;
      // Clamp to 1-100 (minimum 1% so users recognize it's a progress bar)
      progress = Math.max(1, Math.min(100, progress));
    } else {
      // Edge case: payroll is on the 1st, so progress is always 100
      progress = 100;
    }
  } else if (isCurrentMonth && isToday) {
    progress = 100;
  }

  // Calculate countdown text
  const pt = t.components.nextPayrollCard;
  let text: string;

  if (isToday) {
    // Payroll day - show three dashes
    text = "---";
  } else if (!isPast) {
    // Before payroll - show countdown
    const diffMs = payrollDayStart.getTime() - now.getTime();
    const totalHours = Math.floor(diffMs / (1000 * 60 * 60));
    const totalMinutes = Math.floor(diffMs / (1000 * 60));
    const days = countMidnightCrossings(today, payrollDayStart);
    const hours = totalHours % 24;
    const minutes = totalMinutes % 60;

    // Less than 36 hours: show days (if any), hours, and minutes
    if (totalHours < 36) {
      if (days > 0) {
        text = interpolate(pt.inDaysHoursAndMinutes, { days, hours, minutes });
      } else {
        text = interpolate(pt.inHoursAndMinutes, { hours, minutes });
      }
    } else {
      // More than 36 hours: show days and hours only
      text = interpolate(pt.inDaysAndHours, { days, hours });
    }
  } else {
    // After payroll - show how long ago
    const daysAgo = countMidnightCrossings(payrollDayStart, today);
    if (daysAgo === 1) {
      text = pt.oneDayAgo;
    } else {
      text = interpolate(pt.daysAgo, { days: daysAgo });
    }
  }

  return {
    text,
    isToday,
    isPast,
    progress,
  };
}

/**
 * Hook that provides a live countdown to the next payroll date
 * Updates every second when within 36 hours, every minute otherwise
 *
 * @returns Object with text, isToday flag, isPast flag, and progress percentage
 */
export function usePayrollCountdown({
  payrollDay,
  selectedMonth,
  locale,
  t,
}: UsePayrollCountdownOptions): UsePayrollCountdownResult {
  // Track whether we've hydrated to avoid server/client mismatch
  const isHydratedRef = useRef(false);

  // Create a stable key from inputs to reset state when they change
  const inputKey = useMemo(
    () => `${payrollDay}-${selectedMonth.getFullYear()}-${selectedMonth.getMonth()}-${locale}`,
    [payrollDay, selectedMonth, locale]
  );

  // Initial state: safe for SSR (shows placeholder)
  // Progress starts at 0 to prevent animation before we know we're between 1st and payroll day
  const [result, setResult] = useState<UsePayrollCountdownResult>({
    text: "---",
    isToday: false,
    isPast: false,
    progress: 0,
  });
  const [stateKey, setStateKey] = useState(inputKey);

  // Track interval frequency using ref to avoid re-triggering effects
  const intervalMsRef = useRef<number>(60000);
  const [intervalTrigger, setIntervalTrigger] = useState(0);

  // Reset state when inputs change
  if (inputKey !== stateKey) {
    setStateKey(inputKey);
    setResult({ text: "---", isToday: false, isPast: false, progress: 0 });
  }

  // Memoized update function that calculates countdown
  const computeCountdown = useCallback(() => {
    const countdownResult = calculatePayrollCountdown(
      payrollDay,
      selectedMonth,
      locale,
      t
    );

    // Determine new interval based on time until payroll
    const now = new Date();
    const payrollDate = adjustPayrollDate(
      payrollDay,
      selectedMonth.getMonth(),
      selectedMonth.getFullYear(),
      locale
    );
    const payrollDayStart = new Date(
      payrollDate.getFullYear(),
      payrollDate.getMonth(),
      payrollDate.getDate(),
      0, 0, 0, 0
    );

    const diffMs = payrollDayStart.getTime() - now.getTime();
    const hoursUntil = diffMs / (1000 * 60 * 60);
    const needsFrequentUpdates = hoursUntil > 0 && hoursUntil < 36;
    const newIntervalMs = needsFrequentUpdates ? 1000 : 60000;

    return {
      result: countdownResult,
      intervalMs: newIntervalMs,
    };
  }, [payrollDay, selectedMonth, locale, t]);

  // Hydration and input change effect
  useEffect(() => {
    const computed = computeCountdown();

    queueMicrotask(() => {
      setResult(computed.result);

      if (computed.intervalMs !== intervalMsRef.current) {
        intervalMsRef.current = computed.intervalMs;
        setIntervalTrigger((prev) => prev + 1);
      }
    });

    isHydratedRef.current = true;
  }, [computeCountdown]);

  // Interval effect: updates countdown periodically
  useEffect(() => {
    if (!isHydratedRef.current) {
      return;
    }

    const interval = setInterval(() => {
      const computed = computeCountdown();
      setResult(computed.result);

      if (computed.intervalMs !== intervalMsRef.current) {
        intervalMsRef.current = computed.intervalMs;
        setIntervalTrigger((prev) => prev + 1);
      }
    }, intervalMsRef.current);

    return () => clearInterval(interval);
  }, [computeCountdown, intervalTrigger]);

  return result;
}
