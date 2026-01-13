/**
 * Wagey Usage Tracking Types
 *
 * Types for managing Wagey AI assistant access and usage limits
 * based on subscription tiers.
 */

import type { SubscriptionTier } from "@/lib/subscription/getUserTier";

/**
 * Structure stored in profiles.wagey_invocations JSONB column
 */
export type WageyInvocations = {
  readonly count: number;
  readonly month: string | null; // Format: "YYYY-MM"
};

/**
 * Access level now uses the centralized SubscriptionTier type
 * Simplified from 5 levels to 3: "free" | "pro" | "max"
 */
export type WageyAccessLevel = SubscriptionTier;

/**
 * Trial message limit for free users testing Wagey (client-side only, resets on navigation)
 */
export const WAGEY_TRIAL_LIMIT = 3;

/**
 * Complete access result returned by DAL functions
 */
export type WageyAccessResult = {
  /** User's access level based on subscription/profile */
  readonly level: WageyAccessLevel;
  /** Whether user can access Wagey chat (false for free tier) */
  readonly hasAccess: boolean;
  /** Monthly message limit (null = unlimited for grandfathered) */
  readonly limit: number | null;
  /** Messages used this month */
  readonly used: number;
  /** Messages remaining this month (null = unlimited) */
  readonly remaining: number | null;
  /** First day of next month when limit resets */
  readonly resetDate: Date | null;
};

/**
 * Result from atomic increment RPC function
 */
export type WageyInvocationResult = {
  /** Whether the invocation was allowed */
  readonly allowed: boolean;
  /** Current count after this invocation */
  readonly count: number;
  /** Remaining invocations this month */
  readonly remaining: number;
};

/**
 * Monthly message limits per tier
 * Updated: Pro tier increased from 30 to 40 messages
 * Note: Free users get WAGEY_TRIAL_LIMIT as a one-time trial (resets monthly like other tiers)
 */
export const WAGEY_LIMITS: Record<SubscriptionTier, number> = {
  free: WAGEY_TRIAL_LIMIT,
  pro: 40,
  max: 90,
};

/**
 * Get the limit for an access level
 */
export function getWageyLimit(level: WageyAccessLevel): number | null {
  return WAGEY_LIMITS[level];
}

/**
 * Calculate the reset date (first of next month)
 */
export function getResetDate(): Date {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth() + 1, 1);
}

/**
 * Get current month in YYYY-MM format
 */
export function getCurrentMonth(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

/**
 * Calculate days until reset (first of next month)
 */
export function getDaysUntilReset(): number {
  const now = new Date();
  const resetDate = getResetDate();
  const diffTime = resetDate.getTime() - now.getTime();
  return Math.ceil(diffTime / (1000 * 60 * 60 * 24));
}
