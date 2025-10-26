// lib/subscription/hasProAccess.ts
import type { Subscription, UserProfile } from '@/app/[locale]/(app)/settings/subscription/_data/getSubscription';

/**
 * Determines if a user has Pro-level access.
 * Returns true if:
 * - User is grandfathered (before_paywall: true), OR
 * - User has an active subscription
 */
export function hasProAccess(
  subscription: Subscription | null,
  profile: UserProfile | null
): boolean {
  // Grandfathered users get lifetime Pro access
  if (profile?.before_paywall === true) {
    return true;
  }

  // Active subscribers get Pro access
  if (subscription && subscription.status === 'active') {
    return true;
  }

  return false;
}

/**
 * Extracts unique months (YYYY-MM format) from an array of shift dates.
 * @param shifts Array of objects with shift_date property (YYYY-MM-DD format)
 * @returns Set of unique months in YYYY-MM format
 */
export function getUniqueShiftMonths(
  shifts: Array<{ shift_date: string }>
): Set<string> {
  const months = new Set<string>();

  for (const shift of shifts) {
    // Extract YYYY-MM from YYYY-MM-DD
    const match = shift.shift_date.match(/^(\d{4}-\d{2})/);
    if (match) {
      months.add(match[1]);
    }
  }

  return months;
}

/**
 * Formats a YYYY-MM string to a readable Norwegian month format.
 * Example: "2025-01" -> "januar 2025"
 */
export function formatMonth(yearMonth: string): string {
  const [year, month] = yearMonth.split('-');
  const date = new Date(parseInt(year), parseInt(month) - 1, 1);

  const monthName = date.toLocaleDateString('nb-NO', { month: 'long' });
  return `${monthName} ${year}`;
}
