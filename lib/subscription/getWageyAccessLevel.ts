/**
 * Wagey Access Level Helper
 *
 * Determines user's Wagey access level based on subscription and profile data.
 */

import type { Subscription, UserProfile } from "@/lib/services/subscription";
import { ENV } from "@/lib/services/config";
import type { WageyAccessLevel } from "@/lib/wagey/types";

/**
 * Legacy price IDs for backward compatibility
 * These are old Stripe price IDs that were used before the current ones
 */
const LEGACY_PRO_PRICE_IDS = ["price_1RzQ85Qiotkj8G58AO6st4fh"];
const LEGACY_MAX_PRICE_IDS = ["price_1RzQC1Qiotkj8G58tYo4U5oO"];

/**
 * Determines user's Wagey access level based on subscription status and profile
 *
 * Priority order:
 * 1. Grandfathered users (before_paywall === true) get unlimited access
 * 2. Max subscribers (active + Max price) get 20 messages/month
 * 3. Pro subscribers (active + Pro price) get 10 messages/month
 * 4. Everyone else is free tier (no access)
 *
 * @param subscription - User's subscription record (null if free tier)
 * @param profile - User's profile record (null if missing)
 * @returns WageyAccessLevel - "grandfathered" | "max" | "pro" | "free"
 */
export function getWageyAccessLevel(
  subscription: Subscription | null,
  profile: UserProfile | null
): WageyAccessLevel {
  // Grandfathered users get unlimited access regardless of subscription
  if (profile?.before_paywall === true) {
    return "grandfathered";
  }

  // Check for active subscription
  if (!subscription || subscription.status !== "active") {
    return "free";
  }

  const priceId = subscription.price_id;

  // Max tier check (monthly + yearly + legacy)
  const isMax =
    priceId === ENV.MAX_PRICE_ID ||
    priceId === ENV.MAX_YEARLY_PRICE_ID ||
    LEGACY_MAX_PRICE_IDS.includes(priceId ?? "");

  if (isMax) {
    return "max";
  }

  // Pro tier check (monthly + yearly + legacy)
  const isPro =
    priceId === ENV.PRO_PRICE_ID ||
    priceId === ENV.PRO_YEARLY_PRICE_ID ||
    LEGACY_PRO_PRICE_IDS.includes(priceId ?? "");

  if (isPro) {
    return "pro";
  }

  // Unknown price_id with active subscription - treat as free
  // This shouldn't happen in practice but handles edge cases
  return "free";
}
