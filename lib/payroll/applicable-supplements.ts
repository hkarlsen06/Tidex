/**
 * Utility functions for filtering applicable supplements by time window
 *
 * Used to show users which predefined supplements apply to a specific shift,
 * so they can edit them in the custom supplements editor.
 */

import type { SupplementRule } from "./types";

/**
 * Get next weekday (1-7 Mon-Sun, wraps around)
 */
function getNextWeekday(weekday: number): number {
  return weekday === 7 ? 1 : weekday + 1;
}

/**
 * Get ALL supplement rules for a specific weekday (not filtered by time)
 *
 * Used to save non-visible rules alongside user edits, so expanding
 * the shift later won't result in zero supplements for the new time range.
 *
 * @param weekday - Weekday number (1-7, Mon-Sun)
 * @param rules - Predefined supplement rules
 * @returns All rules for this weekday (without days field)
 */
export function getAllWeekdaySupplements(
  weekday: number,
  rules: SupplementRule[]
): Omit<SupplementRule, "days">[] {
  return rules
    .filter((rule) => rule.days.includes(weekday))
    .map((rule) => ({
      from: rule.from,
      to: rule.to,
      rate: rule.rate,
      percent: rule.percent,
    }));
}

/**
 * Convert HH:MM time string to minutes from midnight
 */
function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}

/**
 * Check if two time ranges overlap
 * Handles cross-midnight shifts correctly
 *
 * @param shiftStart - Shift start time in minutes
 * @param shiftEnd - Shift end time in minutes (may be > 1440 for cross-midnight)
 * @param ruleFrom - Rule start time in minutes
 * @param ruleTo - Rule end time in minutes (may be > 1440 for cross-midnight)
 * @returns true if the ranges overlap
 */
function rangesOverlap(
  shiftStart: number,
  shiftEnd: number,
  ruleFrom: number,
  ruleTo: number
): boolean {
  // Ranges overlap if neither ends before the other starts
  return shiftStart < ruleTo && ruleFrom < shiftEnd;
}

/**
 * Get applicable supplement rules for a shift's time window
 *
 * Returns the original rules that overlap with the shift's time window,
 * keeping the original from/to times (not adjusted to shift boundaries).
 *
 * For cross-midnight shifts (e.g., Mon 23:00 - 07:00), this also checks:
 * - Rules for the start day (Monday) that overlap with 23:00-24:00 portion
 * - Rules for the next day (Tuesday) that overlap with 00:00-07:00 portion
 *
 * @param startTime - Shift start time (HH:MM)
 * @param endTime - Shift end time (HH:MM)
 * @param weekday - Weekday number (1-7, Mon-Sun) of the shift start date
 * @param rules - Predefined supplement rules
 * @returns Rules that apply to this shift (without days field, for custom supplements format)
 */
export function getApplicableSupplements(
  startTime: string,
  endTime: string,
  weekday: number,
  rules: SupplementRule[]
): Omit<SupplementRule, "days">[] {
  const shiftStart = toMinutes(startTime);
  let shiftEnd = toMinutes(endTime);

  // Handle cross-midnight shifts
  const isCrossMidnight = shiftEnd <= shiftStart;
  if (isCrossMidnight) {
    shiftEnd += 24 * 60; // Add 24 hours
  }

  const applicable: Omit<SupplementRule, "days">[] = [];
  const nextWeekday = getNextWeekday(weekday);

  for (const rule of rules) {
    const appliesToStartDay = rule.days.includes(weekday);
    const appliesToNextDay = rule.days.includes(nextWeekday);

    // Skip rules that don't apply to either relevant day
    if (!appliesToStartDay && !appliesToNextDay) {
      continue;
    }

    const ruleFrom = toMinutes(rule.from);
    let ruleTo = toMinutes(rule.to);

    // Handle cross-midnight rules
    if (ruleTo < ruleFrom) {
      ruleTo += 24 * 60;
    }

    // Check overlap with start day (if rule applies to start day)
    if (appliesToStartDay && rangesOverlap(shiftStart, shiftEnd, ruleFrom, ruleTo)) {
      applicable.push({
        from: rule.from,
        to: rule.to,
        rate: rule.rate,
        percent: rule.percent,
      });
      continue;
    }

    // For cross-midnight shifts, check if next-day rules apply to the 00:00+ portion
    if (isCrossMidnight && appliesToNextDay) {
      // Next-day rules are shifted +24h to align with our extended timeline
      const nextDayRuleFrom = ruleFrom + 24 * 60;
      const nextDayRuleTo = ruleTo + 24 * 60;
      if (rangesOverlap(shiftStart, shiftEnd, nextDayRuleFrom, nextDayRuleTo)) {
        applicable.push({
          from: rule.from,
          to: rule.to,
          rate: rule.rate,
          percent: rule.percent,
        });
      }
    }
  }

  // Remove duplicates (same from/to/rate/percent)
  const seen = new Set<string>();
  return applicable.filter((rule) => {
    const key = `${rule.from}-${rule.to}-${rule.rate ?? ""}-${rule.percent ?? ""}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}
