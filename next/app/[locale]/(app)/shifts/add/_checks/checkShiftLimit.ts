'use server';

import { verifySession } from '@/data-access/auth';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { getUserSubscriptionData, getUserTier } from '@/data-access/subscription';
import { getUniqueShiftMonths } from '@/lib/subscription/hasProAccess';

export interface ShiftLimitCheckResult {
  allowed: boolean;
  existingMonths?: string[];
  reason?: string;
  isFreeTier: boolean;
}

/**
 * Checks if a user can add shifts in a specific month based on their subscription tier.
 * Free tier users can only have shifts in one month at a time.
 *
 * @param targetMonth - The month being added to (YYYY-MM format)
 * @returns Result indicating if allowed and which months currently have shifts
 */
export async function checkShiftLimit(targetMonth: string): Promise<ShiftLimitCheckResult> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Fetch subscription status and determine tier
  const { subscription, profile } = await getUserSubscriptionData(user.id);
  const tier = getUserTier(subscription, profile);

  // If user has Pro or Max tier, allow all months
  if (tier !== "free") {
    return { allowed: true, isFreeTier: false };
  }

  const isFreeTier = true;

  // User is on free tier - check existing shifts (exclude soft-deleted)
  const { data: existingShifts, error } = await supabase
    .from('user_shifts')
    .select('shift_date')
    .eq('user_id', user.id)
    .is('deleted_at', null);

  if (error) {
    console.error('Error fetching shifts for limit check:', error);
    return { allowed: false, reason: 'Database error', isFreeTier };
  }

  // If no existing shifts, allow
  if (!existingShifts || existingShifts.length === 0) {
    return { allowed: true, isFreeTier };
  }

  // Get unique months from existing shifts
  const existingMonths = getUniqueShiftMonths(existingShifts);

  // If user already has shifts ONLY in the target month, allow (adding to same month)
  if (existingMonths.size === 1 && existingMonths.has(targetMonth)) {
    return { allowed: true, isFreeTier };
  }

  // If user has no existing shifts, allow
  if (existingMonths.size === 0) {
    return { allowed: true, isFreeTier };
  }

  // If user has shifts in other month(s), block
  return {
    allowed: false,
    existingMonths: Array.from(existingMonths),
    reason: 'Free tier users can only have shifts in one month',
    isFreeTier
  };
}
