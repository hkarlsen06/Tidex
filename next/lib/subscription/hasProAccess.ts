// lib/subscription/hasProAccess.ts
import type { Subscription, UserProfile } from '@/data-access/subscription';
import { getUserTier } from './getUserTier';

/**
 * Entitled subscription statuses
 * - active: Normal active subscription
 * - trialing: In trial period
 * - grace: In grace period (payment failed but still entitled)
 */
const ENTITLED_STATUSES = ['active', 'trialing', 'grace'];

/**
 * Determines if a user has Pro-level access (Pro or Max tier).
 * Returns true if user's tier is anything other than "free".
 *
 * Uses centralized getUserTier() for consistent tier determination.
 */
export function hasProAccess(
  subscription: Subscription | null,
  profile: UserProfile | null
): boolean {
  return getUserTier(subscription, profile) !== "free";
}

/**
 * Get the subscription provider if user has an active subscription
 */
export function getActiveProvider(
  subscription: Subscription | null
): 'stripe' | 'apple' | 'admin_trial' | null {
  if (!subscription) return null;
  if (!ENTITLED_STATUSES.includes(subscription.status)) return null;
  return subscription.provider ?? 'stripe';
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
