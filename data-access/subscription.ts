'use server';

import { cacheTag } from 'next/cache';
import { verifySession } from '@/data-access/auth';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export interface Subscription {
  id: string;
  user_id: string;
  stripe_customer_id: string | null;
  stripe_subscription_id: string | null;
  status: string;
  current_period_end: string | null;
  created_at: string;
  updated_at: string;
  price_id: string | null;
  cancel_at_period_end: boolean;
  canceled_at: string | null;
  cancel_at: string | null;
  cancellation_reason: string | null;
  cancellation_feedback: string | null;
  cancellation_comment: string | null;
}

export interface UserProfile {
  id: string;
  before_paywall: boolean;
  created_at: string;
  updated_at: string;
}

export interface SubscriptionData {
  subscription: Subscription | null;
  profile: UserProfile | null;
}

/**
 * Get user subscription for the authenticated user
 * - Automatically verifies user session matches provided userId
 */
export async function getUserSubscription(userId: string): Promise<Subscription | null> {
  'use cache: private';
  cacheTag(`user-${userId}`, 'user-subscription');
  try {
    const { user } = await verifySession();

    // SECURITY: Verify the provided userId matches the authenticated user
    if (user.id !== userId) {
      throw new Error('User ID mismatch - potential security violation');
    }

    const supabase = await createSupabaseServerClient();

    const { data, error } = await supabase
      .from('subscriptions')
      .select('*')
      .eq('user_id', user.id)
      .single();

    if (error) {
      // If no subscription found, that's okay - user is on free plan
      if (error.code === 'PGRST116') {
        return null;
      }
      logger.error('Failed to fetch user subscription:', error);
      return null;
    }

    return data;
  } catch (error) {
    logger.error('Unexpected error fetching subscription:', error);
    return null;
  }
}

/**
 * Get user subscription data including profile for the authenticated user
 * - Automatically verifies user session matches provided userId
 */
export async function getUserSubscriptionData(userId: string): Promise<SubscriptionData> {
  'use cache: private';
  cacheTag(`user-${userId}`, 'user-subscription');
  try {
    const { user } = await verifySession();

    // SECURITY: Verify the provided userId matches the authenticated user
    if (user.id !== userId) {
      throw new Error('User ID mismatch - potential security violation');
    }

    const supabase = await createSupabaseServerClient();

    // Fetch both subscription and profile data
    const [subscriptionResult, profileResult] = await Promise.all([
      supabase
        .from('subscriptions')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single(),
    ]);

    const subscription = subscriptionResult.error && subscriptionResult.error.code === 'PGRST116'
      ? null
      : subscriptionResult.data;

    const profile = profileResult.error ? null : profileResult.data;

    if (subscriptionResult.error && subscriptionResult.error.code !== 'PGRST116') {
      logger.error('Failed to fetch user subscription:', subscriptionResult.error);
    }

    if (profileResult.error) {
      logger.error('Failed to fetch user profile:', profileResult.error);
    }

    return { subscription, profile };
  } catch (error) {
    logger.error('Unexpected error fetching subscription data:', error);
    return { subscription: null, profile: null };
  }
}
