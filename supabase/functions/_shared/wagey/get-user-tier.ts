/**
 * Centralized Subscription Tier Determination
 *
 * This is the single source of truth for determining a user's subscription tier.
 * All paywall checks should use this function to ensure consistent behavior.
 *
 * Tier logic:
 * - Grandfathered users (before_paywall: true) get Pro tier automatically
 * - If a grandfathered user has a Max subscription, they get Max tier
 * - Otherwise, tier is determined by active subscription (Pro/Max/Free)
 *
 * Product ID is the single source of truth:
 * - Edge functions (Stripe webhook, Apple webhooks) normalize external IDs to internal product_id
 * - Internal product IDs: pro_monthly, pro_yearly, max_monthly, max_yearly
 * - Apple product IDs: no.tidex.pro, no.tidex.pro.year, no.tidex.max, no.tidex.max.year
 */

type Subscription = {
  readonly status: string;
  readonly product_id: string | null;
  readonly current_period_end: string | null;
  readonly price_id: string | null;
  readonly provider: "stripe" | "apple" | "admin_trial";
};

type UserProfile = {
  readonly before_paywall: boolean;
};

/**
 * Subscription tier levels
 * - free: No active subscription
 * - pro: Pro subscription or grandfathered user
 * - max: Max subscription
 */
export type SubscriptionTier = "free" | "pro" | "max";

/**
 * Entitled subscription statuses (single source of truth)
 * - active: Normal active subscription
 * - trialing: In trial period
 * - grace: In grace period (payment failed but still entitled)
 */
const ENTITLED_STATUSES = ["active", "trialing", "grace"] as const;

/**
 * Internal and Apple product IDs for each tier
 * Edge functions normalize Stripe price_id → internal product_id
 */
const MAX_PRODUCT_IDS = [
  "max_monthly",
  "max_yearly",
  "no.tidex.max",
  "no.tidex.max.year",
] as const;

const PRO_PRODUCT_IDS = [
  "pro_monthly",
  "pro_yearly",
  "no.tidex.pro",
  "no.tidex.pro.year",
] as const;

/**
 * Check if subscription has an entitled status and valid period
 */
function hasEntitledSubscription(subscription: Subscription | null): boolean {
  if (!subscription) return false;
  if (
    !ENTITLED_STATUSES.includes(
      subscription.status as (typeof ENTITLED_STATUSES)[number]
    )
  )
    return false;

  // Verify period hasn't expired
  if (subscription.current_period_end) {
    if (new Date(subscription.current_period_end) <= new Date()) return false;
  }
  return true;
}

/**
 * Check if subscription is for Max tier based on product_id
 */
function isMaxSubscription(subscription: Subscription | null): boolean {
  if (!subscription?.product_id) return false;
  return MAX_PRODUCT_IDS.includes(
    subscription.product_id as (typeof MAX_PRODUCT_IDS)[number]
  );
}

/**
 * Check if subscription is for Pro tier based on product_id
 */
function isProSubscription(subscription: Subscription | null): boolean {
  if (!subscription?.product_id) return false;
  return PRO_PRODUCT_IDS.includes(
    subscription.product_id as (typeof PRO_PRODUCT_IDS)[number]
  );
}

/**
 * Determines subscription tier from subscription and profile data.
 * This is the single source of truth for tier determination.
 *
 * Explicitly checks for each known tier rather than using fallback logic,
 * to ensure unknown subscription types fail safely (as free tier) rather
 * than silently getting elevated access.
 *
 * @param subscription - User's subscription record (null if free tier)
 * @param profile - User's profile record (null if missing)
 * @returns SubscriptionTier - "free" | "pro" | "max"
 */
export function getUserTier(
  subscription: Subscription | null,
  profile: UserProfile | null
): SubscriptionTier {
  // Grandfathered users: Pro unless they have Max subscription
  if (profile?.before_paywall === true) {
    const hasMax =
      isMaxSubscription(subscription) && hasEntitledSubscription(subscription);
    return hasMax ? "max" : "pro";
  }

  // No entitled subscription = free tier
  if (!hasEntitledSubscription(subscription)) {
    return "free";
  }

  // Explicit tier checks for entitled subscriptions
  if (isMaxSubscription(subscription)) return "max";
  if (isProSubscription(subscription)) return "pro";

  // Unknown subscription type - log warning and default to free for safety
  // This ensures new subscription types fail safely rather than getting Pro access
  console.warn(
    `[getUserTier] Unknown subscription type: price_id=${subscription?.price_id}, product_id=${subscription?.product_id}, provider=${subscription?.provider}`
  );
  return "free";
}
