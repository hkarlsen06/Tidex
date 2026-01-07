'use server';

import Stripe from 'stripe';
import { logger } from '@/lib/logger';
import { verifySession } from '@/data-access/auth';
import { enforceNotImpersonating } from '@/lib/auth/impersonation';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { revalidateTag } from 'next/cache';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2025-10-29.clover',
});

// Maps Stripe price IDs to internal product IDs (same as webhook)
const STRIPE_PRICE_TO_PRODUCT: Record<string, string> = {
  "price_1RzQ85Qiotkj8G58AO6st4fh": "pro_monthly",
  "price_1RzQC1Qiotkj8G58tYo4U5oO": "max_monthly",
};

function mapStripePriceToProductId(priceId: string | null): string | null {
  if (!priceId) return null;
  return STRIPE_PRICE_TO_PRODUCT[priceId] ?? priceId;
}

export type RestoreResultError =
  | 'already_exists'
  | 'not_found'
  | 'no_valid_subscription'
  | 'database_error'
  | 'stripe_error';

export interface RestoreResult {
  success: boolean;
  error?: RestoreResultError;
}

/**
 * Helper to get period_end from subscription.
 * In newer Stripe API versions, these may be on items rather than the subscription.
 */
function getPeriodEnd(sub: Stripe.Subscription): number | null {
  // Access through items (safer for newer API versions)
  const itemPeriodEnd = sub.items?.data?.[0]?.current_period_end;
  if (typeof itemPeriodEnd === 'number') return itemPeriodEnd;

  // Fallback: try direct access (may exist at runtime even if not in types)
  const subRecord = sub as unknown as Record<string, unknown>;
  const directPeriodEnd = subRecord.current_period_end;
  if (typeof directPeriodEnd === 'number') return directPeriodEnd;

  return null;
}

/**
 * Helper to get period_start from subscription.
 */
function getPeriodStart(sub: Stripe.Subscription): number | null {
  const itemPeriodStart = sub.items?.data?.[0]?.current_period_start;
  if (typeof itemPeriodStart === 'number') return itemPeriodStart;

  const subRecord = sub as unknown as Record<string, unknown>;
  const directPeriodStart = subRecord.current_period_start;
  if (typeof directPeriodStart === 'number') return directPeriodStart;

  return null;
}

/**
 * Access-aware tier ranking for subscription selection.
 * Returns tier number (lower = better) or null if subscription should be ignored.
 */
function getSubscriptionTier(sub: Stripe.Subscription): number | null {
  const now = Date.now() / 1000;

  // Tier A: Active access
  if (sub.status === 'trialing' || sub.status === 'active') return 1;

  // Tier B: Dunning (still has access)
  if (sub.status === 'past_due') return 2;

  // Tier C: Canceled but still in period
  const periodEnd = getPeriodEnd(sub);
  if (sub.status === 'canceled' && periodEnd && periodEnd > now) return 3;

  // Ignore: unpaid, incomplete, incomplete_expired, paused
  return null;
}

/**
 * Compare two subscriptions and return true if candidate is better than current.
 */
function isBetterSubscription(
  candidate: Stripe.Subscription | null,
  current: Stripe.Subscription | null
): boolean {
  if (!candidate) return false;
  if (!current) return getSubscriptionTier(candidate) !== null;

  const candidateTier = getSubscriptionTier(candidate);
  const currentTier = getSubscriptionTier(current);

  if (candidateTier === null) return false;
  if (currentTier === null) return true;

  // Lower tier number = better
  if (candidateTier !== currentTier) return candidateTier < currentTier;

  // Same tier: prefer later period_end, then later created
  const candidatePeriodEnd = getPeriodEnd(candidate) ?? 0;
  const currentPeriodEnd = getPeriodEnd(current) ?? 0;

  if (candidatePeriodEnd !== currentPeriodEnd) {
    return candidatePeriodEnd > currentPeriodEnd;
  }
  return candidate.created > current.created;
}

/**
 * Upsert subscription row with the same logic as the Stripe webhook.
 */
async function upsertSubscriptionRow(
  userId: string,
  customerId: string,
  sub: Stripe.Subscription
): Promise<{ error: { code?: string; message: string } | null }> {
  const supabase = createSupabaseServiceClient();

  const status = sub.status;
  const periodStartUnix = getPeriodStart(sub);
  const periodStartISO = periodStartUnix ? new Date(periodStartUnix * 1000).toISOString() : null;
  const periodEndUnix = getPeriodEnd(sub);
  const periodEndISO = periodEndUnix ? new Date(periodEndUnix * 1000).toISOString() : null;
  const priceId = sub.items?.data?.[0]?.price?.id ?? null;
  const productId = mapStripePriceToProductId(priceId);

  // Cancellation fields
  const cancelAtPeriodEnd = sub.cancel_at_period_end ?? false;
  const canceledAtUnix = sub.canceled_at ?? null;
  const canceledAtISO = canceledAtUnix ? new Date(canceledAtUnix * 1000).toISOString() : null;
  const cancelAtUnix = sub.cancel_at ?? null;
  const cancelAtISO = cancelAtUnix ? new Date(cancelAtUnix * 1000).toISOString() : null;

  // Cancellation details
  const cancellationDetails = sub.cancellation_details ?? null;
  const cancellationReason = cancellationDetails?.reason ?? null;
  const cancellationFeedback = cancellationDetails?.feedback ?? null;
  const cancellationComment = cancellationDetails?.comment ?? null;

  const payload = {
    user_id: userId,
    provider: 'stripe' as const,
    provider_subscription_id: sub.id,
    stripe_customer_id: customerId,
    stripe_subscription_id: sub.id,
    status,
    product_id: productId,
    current_period_start: periodStartISO,
    current_period_end: periodEndISO,
    cancel_at_period_end: cancelAtPeriodEnd,
    canceled_at: canceledAtISO,
    cancel_at: cancelAtISO,
    cancellation_reason: cancellationReason,
    cancellation_feedback: cancellationFeedback,
    cancellation_comment: cancellationComment,
    ...(priceId ? { price_id: priceId } : {}),
  };

  const { error } = await supabase
    .from('subscriptions')
    .upsert(payload, { onConflict: 'user_id' });

  if (error) {
    return { error: { code: error.code, message: error.message } };
  }

  return { error: null };
}

/**
 * Restore a user's subscription by searching Stripe for any customer/subscription
 * linked to their user ID or email.
 */
export async function restoreSubscription(): Promise<RestoreResult> {
  try {
    // 1. Verify session and block impersonation
    const { user } = await verifySession();
    await enforceNotImpersonating('restore_subscription');

    const supabase = createSupabaseServiceClient();

    // 2. Check if subscription already exists
    const { data: existing, error: existingError } = await supabase
      .from('subscriptions')
      .select('id, stripe_subscription_id')
      .eq('user_id', user.id)
      .maybeSingle();

    if (existingError) {
      logger.error('Error checking existing subscription:', existingError);
      return { success: false, error: 'database_error' };
    }

    if (existing) {
      return { success: false, error: 'already_exists' };
    }

    // 3. Search Stripe for customers by metadata first (limit 5 for duplicates)
    let customers: Stripe.ApiSearchResult<Stripe.Customer>;
    try {
      customers = await stripe.customers.search({
        query: `metadata['supabase_uid']:'${user.id}'`,
        limit: 5,
      });

      // 4. Fallback: search by email if metadata search fails
      if (customers.data.length === 0 && user.email) {
        customers = await stripe.customers.search({
          query: `email:'${user.email}'`,
          limit: 5,
        });
      }
    } catch (error) {
      logger.error('Stripe search error:', error);
      return { success: false, error: 'stripe_error' };
    }

    if (customers.data.length === 0) {
      return { success: false, error: 'not_found' };
    }

    // 5. Find best subscription across ALL customers
    let bestCustomer: Stripe.Customer | null = null;
    let bestSub: Stripe.Subscription | null = null;

    for (const customer of customers.data) {
      try {
        const subs = await stripe.subscriptions.list({
          customer: customer.id,
          status: 'all',
          limit: 20,
          expand: ['data.items.data.price'],
        });

        for (const sub of subs.data) {
          if (isBetterSubscription(sub, bestSub)) {
            bestCustomer = customer;
            bestSub = sub;
          }
        }
      } catch (error) {
        logger.warn('Error fetching subscriptions for customer:', customer.id, error);
        // Continue checking other customers
      }
    }

    if (!bestSub || !bestCustomer) {
      return { success: false, error: 'no_valid_subscription' };
    }

    // 6. Update customer metadata to link to this user (for future webhooks)
    try {
      await stripe.customers.update(bestCustomer.id, {
        metadata: { supabase_uid: user.id },
      });
    } catch (error) {
      logger.warn('Failed to update customer metadata:', error);
      // Non-fatal, continue with restore
    }

    // 7. Upsert subscription row
    const { error: upsertError } = await upsertSubscriptionRow(
      user.id,
      bestCustomer.id,
      bestSub
    );

    // Handle unique constraint violation as success (race condition)
    if (upsertError?.code === '23505') {
      revalidateTag(`user-${user.id}`, "max");
      return { success: true };
    }

    if (upsertError) {
      logger.error('Error upserting subscription:', upsertError);
      return { success: false, error: 'database_error' };
    }

    // 8. Invalidate cache
    revalidateTag(`user-${user.id}`, "max");

    logger.info('Subscription restored successfully for user:', user.id);
    return { success: true };
  } catch (error) {
    logger.error('Error restoring subscription:', error);
    return { success: false, error: 'stripe_error' };
  }
}
