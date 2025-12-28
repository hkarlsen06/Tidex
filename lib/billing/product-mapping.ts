/**
 * Product ID Mapping Configuration
 *
 * Maps provider-specific product/price IDs to internal product IDs.
 * This ensures consistent entitlement tracking across Stripe and Apple IAP.
 */

// ---------- Internal Product IDs ----------
// These are the canonical product identifiers used in the database
// Matches the existing Stripe tiers: Pro and Max, each with monthly/yearly
export const INTERNAL_PRODUCTS = {
  PRO_MONTHLY: 'pro_monthly',
  PRO_YEARLY: 'pro_yearly',
  MAX_MONTHLY: 'max_monthly',
  MAX_YEARLY: 'max_yearly',
} as const;

export type InternalProductId = (typeof INTERNAL_PRODUCTS)[keyof typeof INTERNAL_PRODUCTS];

// ---------- Apple Product IDs ----------
// These must match the products configured in App Store Connect
// Naming convention: no.tidex.<tier>.<period>
export const APPLE_PRODUCT_IDS = {
  PRO_MONTHLY: 'no.tidex.pro.monthly',
  PRO_YEARLY: 'no.tidex.pro.yearly',
  MAX_MONTHLY: 'no.tidex.max.monthly',
  MAX_YEARLY: 'no.tidex.max.yearly',
} as const;

export type AppleProductId = (typeof APPLE_PRODUCT_IDS)[keyof typeof APPLE_PRODUCT_IDS];

// All allowed Apple product IDs (for validation)
export const ALL_APPLE_PRODUCT_IDS: AppleProductId[] = Object.values(APPLE_PRODUCT_IDS);

// ---------- Stripe Price IDs ----------
// These are the Stripe price IDs from your Stripe dashboard
export const STRIPE_PRICE_IDS = {
  // Pro tier
  PRO_MONTHLY: process.env.NEXT_PUBLIC_PRO_PRICE_ID || 'price_1RzQ85Qiotkj8G58AO6st4fh',
  PRO_YEARLY: process.env.NEXT_PUBLIC_PRO_YEARLY_ID || '',
  // Max tier
  MAX_MONTHLY: process.env.NEXT_PUBLIC_MAX_PRICE_ID || 'price_1RzQC1Qiotkj8G58tYo4U5oO',
  MAX_YEARLY: process.env.NEXT_PUBLIC_MAX_YEARLY_ID || '',
} as const;

// Legacy Stripe price IDs (for backward compatibility)
export const LEGACY_STRIPE_PRICE_IDS: {
  PRO_MONTHLY: readonly string[];
  MAX_MONTHLY: readonly string[];
} = {
  PRO_MONTHLY: ['price_1RzQ85Qiotkj8G58AO6st4fh'],
  MAX_MONTHLY: ['price_1RzQC1Qiotkj8G58tYo4U5oO'],
};

// ---------- Mapping Functions ----------

/**
 * Maps an Apple product ID to an internal product ID
 */
export function mapAppleToInternal(appleProductId: string): InternalProductId | null {
  const mapping: Record<string, InternalProductId> = {
    [APPLE_PRODUCT_IDS.PRO_MONTHLY]: INTERNAL_PRODUCTS.PRO_MONTHLY,
    [APPLE_PRODUCT_IDS.PRO_YEARLY]: INTERNAL_PRODUCTS.PRO_YEARLY,
    [APPLE_PRODUCT_IDS.MAX_MONTHLY]: INTERNAL_PRODUCTS.MAX_MONTHLY,
    [APPLE_PRODUCT_IDS.MAX_YEARLY]: INTERNAL_PRODUCTS.MAX_YEARLY,
  };

  return mapping[appleProductId] ?? null;
}

/**
 * Maps a Stripe price ID to an internal product ID
 */
export function mapStripeToInternal(stripePriceId: string): InternalProductId | null {
  // Check current price IDs
  if (stripePriceId === STRIPE_PRICE_IDS.PRO_MONTHLY) {
    return INTERNAL_PRODUCTS.PRO_MONTHLY;
  }
  if (stripePriceId === STRIPE_PRICE_IDS.PRO_YEARLY) {
    return INTERNAL_PRODUCTS.PRO_YEARLY;
  }
  if (stripePriceId === STRIPE_PRICE_IDS.MAX_MONTHLY) {
    return INTERNAL_PRODUCTS.MAX_MONTHLY;
  }
  if (stripePriceId === STRIPE_PRICE_IDS.MAX_YEARLY) {
    return INTERNAL_PRODUCTS.MAX_YEARLY;
  }

  // Check legacy price IDs
  if (LEGACY_STRIPE_PRICE_IDS.PRO_MONTHLY.includes(stripePriceId)) {
    return INTERNAL_PRODUCTS.PRO_MONTHLY;
  }
  if (LEGACY_STRIPE_PRICE_IDS.MAX_MONTHLY.includes(stripePriceId)) {
    return INTERNAL_PRODUCTS.MAX_MONTHLY;
  }

  return null;
}

/**
 * Validates if an Apple product ID is allowed
 */
export function isValidAppleProduct(productId: string): productId is AppleProductId {
  return ALL_APPLE_PRODUCT_IDS.includes(productId as AppleProductId);
}

// ---------- Tier Information ----------

export type SubscriptionTier = 'free' | 'pro' | 'max';

/**
 * Get the tier for an internal product ID
 */
export function getTierFromProductId(productId: string | null): SubscriptionTier {
  if (!productId) return 'free';

  if (
    productId === INTERNAL_PRODUCTS.PRO_MONTHLY ||
    productId === INTERNAL_PRODUCTS.PRO_YEARLY
  ) {
    return 'pro';
  }

  if (
    productId === INTERNAL_PRODUCTS.MAX_MONTHLY ||
    productId === INTERNAL_PRODUCTS.MAX_YEARLY
  ) {
    return 'max';
  }

  return 'free';
}

/**
 * Check if a product ID grants shift storage entitlement
 */
export function hasShiftStorageEntitlement(productId: string | null): boolean {
  // All paid tiers grant shift storage
  return getTierFromProductId(productId) !== 'free';
}
