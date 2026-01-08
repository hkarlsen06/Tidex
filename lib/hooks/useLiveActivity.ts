"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  ShiftActivity,
  type ShiftActivityData,
  type StoredShiftData,
} from "@/lib/capacitor/shift-activity";
import { isIOSPlatform } from "@/lib/capacitor/platform";
import type { ShiftWithComputations } from "@/lib/payroll/types";

type UseLiveActivityOptions = {
  /** Array of shifts with computed earnings data */
  shifts: ShiftWithComputations[];
  /** User's locale ("no" or "en") */
  locale: string;
  /** Currency symbol to display (e.g., "kr", "$", "€") */
  currencySymbol?: string;
  /** Whether Live Activity management is enabled (default: true) */
  enabled?: boolean;
};

type UseLiveActivityResult = {
  /** Manually start activity for a shift */
  startActivity: (shift: ShiftWithComputations) => Promise<void>;
  /** Manually end the current activity */
  endActivity: () => Promise<void>;
  /** Whether an activity is currently running */
  isActive: boolean;
};

/**
 * Parse shift times into Date objects, handling cross-midnight shifts
 */
function parseShiftTimes(
  shiftDate: string,
  startTime: string,
  endTime: string
): { startDateTime: Date; endDateTime: Date } {
  const [startHours, startMinutes] = startTime.split(":").map(Number);
  const [endHours, endMinutes] = endTime.split(":").map(Number);

  const startDateTime = new Date(shiftDate + "T00:00:00");
  startDateTime.setHours(startHours, startMinutes, 0, 0);

  const endDateTime = new Date(shiftDate + "T00:00:00");
  endDateTime.setHours(endHours, endMinutes, 0, 0);

  // Handle cross-midnight shifts: if end <= start, end is next day
  if (endDateTime <= startDateTime) {
    endDateTime.setDate(endDateTime.getDate() + 1);
  }

  return { startDateTime, endDateTime };
}

/**
 * Determines if a shift is currently ongoing
 */
function isShiftOngoing(shift: ShiftWithComputations): boolean {
  const now = new Date();
  const { startDateTime, endDateTime } = parseShiftTimes(
    shift.shift_date,
    shift.start_time,
    shift.end_time
  );

  return now >= startDateTime && now < endDateTime;
}

/**
 * Calculate initial activity state from shift
 */
function calculateActivityState(shift: ShiftWithComputations): {
  progress: number;
  earnings: number;
  remainingMinutes: number;
} {
  const now = new Date();
  const { startDateTime, endDateTime } = parseShiftTimes(
    shift.shift_date,
    shift.start_time,
    shift.end_time
  );

  const totalMs = endDateTime.getTime() - startDateTime.getTime();
  const elapsedMs = now.getTime() - startDateTime.getTime();
  const progress = Math.min(100, Math.max(0, (elapsedMs / totalMs) * 100));

  // Calculate earnings based on progress and computed gross
  const earnings = (progress / 100) * shift.computed.gross;
  const remainingMinutes = Math.max(
    0,
    Math.ceil((totalMs - elapsedMs) / 60000)
  );

  return { progress, earnings, remainingMinutes };
}

/**
 * Calculate average supplement rate from wage periods
 */
function calculateAverageSupplementRate(shift: ShiftWithComputations): number {
  const periods = shift.computed.wagePeriods;
  if (periods.length === 0) return 0;

  let totalWeightedSupplement = 0;
  let totalMinutes = 0;

  for (const period of periods) {
    const minutes = period.toMin - period.fromMin;
    totalWeightedSupplement += period.supplementRate * minutes;
    totalMinutes += minutes;
  }

  return totalMinutes > 0 ? totalWeightedSupplement / totalMinutes : 0;
}

/**
 * Find the ongoing shift from a list of shifts
 * Checks today's shifts first, then yesterday's cross-midnight shifts
 */
function findOngoingShift(
  shifts: ShiftWithComputations[]
): ShiftWithComputations | null {
  const now = new Date();
  const today = now.toISOString().split("T")[0];

  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayStr = yesterday.toISOString().split("T")[0];

  // Check today's shifts first
  const todayShift = shifts.find(
    (s) => s.shift_date === today && isShiftOngoing(s)
  );
  if (todayShift) return todayShift;

  // Check yesterday's cross-midnight shifts
  const crossMidnightShift = shifts.find((s) => {
    if (s.shift_date !== yesterdayStr) return false;
    // Cross-midnight: end time is less than start time
    if (s.end_time >= s.start_time) return false;
    return isShiftOngoing(s);
  });

  return crossMidnightShift || null;
}

/**
 * Prepare shifts for storage (upcoming shifts for background task)
 */
function prepareShiftsForStorage(
  shifts: ShiftWithComputations[],
  locale: string
): StoredShiftData[] {
  const now = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowStr = tomorrow.toISOString().split("T")[0];
  const todayStr = now.toISOString().split("T")[0];

  // Filter to today and tomorrow's shifts
  return shifts
    .filter((s) => s.shift_date === todayStr || s.shift_date === tomorrowStr)
    .map((shift) => {
      const supplementRate = calculateAverageSupplementRate(shift);
      const hourlyWage =
        shift.computed.paidHours > 0
          ? shift.computed.basePay / shift.computed.paidHours
          : 0;

      return {
        shiftId: shift.id,
        shiftDate: shift.shift_date,
        startTime: shift.start_time,
        endTime: shift.end_time,
        hourlyWage,
        supplementRatePerHour: supplementRate,
        totalGrossEstimate: shift.computed.gross,
        locale,
      };
    });
}

/**
 * Hook for managing iOS Live Activities for ongoing shifts
 *
 * Features:
 * - Automatically starts activity when an ongoing shift is detected
 * - Automatically ends activity when shift ends
 * - Handles app launch during ongoing shift
 * - Saves upcoming shifts to shared storage for background task
 *
 * @example
 * ```tsx
 * const { isActive } = useLiveActivity({
 *   shifts,
 *   locale: "no",
 *   enabled: true,
 * });
 * ```
 */
export function useLiveActivity({
  shifts,
  locale,
  currencySymbol = "kr",
  enabled = true,
}: UseLiveActivityOptions): UseLiveActivityResult {
  const activeActivityRef = useRef<string | null>(null);
  const lastShiftIdRef = useRef<string | null>(null);
  const [isActive, setIsActive] = useState(false);

  const startActivity = useCallback(
    async (shift: ShiftWithComputations) => {
      if (!isIOSPlatform()) return;

      try {
        const { available } = await ShiftActivity.isAvailable();
        if (!available) return;

        const state = calculateActivityState(shift);
        const supplementRate = calculateAverageSupplementRate(shift);

        // Get hourly wage from computed base pay / paid hours
        const hourlyWage =
          shift.computed.paidHours > 0
            ? shift.computed.basePay / shift.computed.paidHours
            : 0;

        const data: ShiftActivityData = {
          shiftId: shift.id,
          shiftDate: shift.shift_date,
          startTime: shift.start_time,
          endTime: shift.end_time,
          hourlyWage,
          supplementRatePerHour: supplementRate,
          totalGrossEstimate: shift.computed.gross,
          locale,
          currencySymbol,
          initialProgress: state.progress,
          initialEarnings: state.earnings,
          remainingMinutes: state.remainingMinutes,
        };

        const result = await ShiftActivity.startActivity(data);
        if (result.success) {
          activeActivityRef.current = result.activityId;
          lastShiftIdRef.current = shift.id;
          setIsActive(true);
        }
      } catch (error) {
        console.error("[LiveActivity] Failed to start activity:", error);
      }
    },
    [locale, currencySymbol]
  );

  const endActivity = useCallback(async () => {
    if (!isIOSPlatform()) return;

    try {
      await ShiftActivity.endActivity();
      activeActivityRef.current = null;
      lastShiftIdRef.current = null;
      setIsActive(false);
    } catch (error) {
      console.error("[LiveActivity] Failed to end activity:", error);
    }
  }, []);

  // Save upcoming shifts to shared storage for background task
  useEffect(() => {
    if (!enabled || !isIOSPlatform()) return;

    const saveShifts = async () => {
      try {
        const storedShifts = prepareShiftsForStorage(shifts, locale);
        await ShiftActivity.saveShiftsToSharedStorage({
          shifts: JSON.stringify(storedShifts),
        });
      } catch (error) {
        console.error("[LiveActivity] Failed to save shifts:", error);
      }
    };

    saveShifts();
  }, [shifts, locale, enabled]);

  // Auto-manage activity based on shift state
  useEffect(() => {
    if (!enabled || !isIOSPlatform()) return;

    const manageActivity = async () => {
      const ongoingShift = findOngoingShift(shifts);

      if (ongoingShift && ongoingShift.id !== lastShiftIdRef.current) {
        // New ongoing shift - start activity
        await startActivity(ongoingShift);
      } else if (!ongoingShift && activeActivityRef.current) {
        // No ongoing shift but activity is running - end it
        await endActivity();
      }
    };

    manageActivity();
  }, [shifts, enabled, startActivity, endActivity]);

  // Check for existing activity on mount (app launched during shift)
  useEffect(() => {
    if (!enabled || !isIOSPlatform()) return;

    const checkExisting = async () => {
      try {
        const { hasActivity, shiftId } =
          await ShiftActivity.getActiveActivity();

        if (hasActivity && shiftId) {
          // Activity exists - check if shift is still ongoing
          const shift = shifts.find((s) => s.id === shiftId);
          if (shift && isShiftOngoing(shift)) {
            activeActivityRef.current = shiftId;
            lastShiftIdRef.current = shiftId;
            setIsActive(true);
          } else {
            // Shift ended - clean up
            await endActivity();
          }
        } else {
          // No activity - check if we should start one
          const ongoingShift = findOngoingShift(shifts);
          if (ongoingShift) {
            await startActivity(ongoingShift);
          }
        }
      } catch (error) {
        console.error("[LiveActivity] Failed to check existing:", error);
      }
    };

    checkExisting();
    // Only run on mount
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled]);

  return {
    startActivity,
    endActivity,
    isActive,
  };
}
