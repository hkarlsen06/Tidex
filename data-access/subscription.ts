/**
 * Subscription Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * Uses SubscriptionService for subscription and profile data.
 *
 * Migration status: Using Effect-based SubscriptionService internally
 */

import "server-only";
import { cache } from "react";
import { cacheTag } from "next/cache";
import { cookies } from "next/headers";
import { Effect } from "effect";
import {
  SubscriptionService,
  type Subscription,
  type UserProfile,
  type SubscriptionData,
} from "@/lib/services/subscription";
import { SubscriptionLive } from "@/lib/layers/app";
import { logger } from "@/lib/logger";
import { verifySession } from "@/data-access/auth";

// Re-export types for backward compatibility
export type { Subscription, UserProfile, SubscriptionData };

// Import and re-export getUserTier for centralized tier logic
import { getUserTier, type SubscriptionTier } from "@/lib/subscription/getUserTier";
export { getUserTier };
export type { SubscriptionTier };

/**
 * Internal implementation of getUserSubscription using Effect
 * @internal - Do not call directly, use getUserSubscription()
 */
async function getUserSubscriptionInternal(
  userId: string
): Promise<Subscription | null> {
  "use cache: private";
  cacheTag(`user-${userId}`, "user-subscription");

  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  await cookies();

  const program = Effect.gen(function* () {
    const subscription = yield* SubscriptionService;
    const data = yield* subscription.getUserSubscription(userId);
    return data;
  }).pipe(Effect.provide(SubscriptionLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return result;
  } catch (error: any) {
    logger.error("Failed to fetch user subscription:", error);
    // Return null on error (free tier fallback)
    return null;
  }
}

/**
 * Get user subscription for the authenticated user
 * - Uses React cache() for request deduplication, scoped by userId
 * - Automatically verifies user session matches provided userId
 * - Returns null if no subscription exists (free tier)
 *
 * Promise wrapper around Effect-based SubscriptionService
 */
export const getUserSubscription = cache(
  async (userId: string): Promise<Subscription | null> => {
    const { user } = await verifySession();

    // SECURITY: Verify the provided userId matches the authenticated user
    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getUserSubscriptionInternal(userId);
  }
);

/**
 * Internal implementation of getUserSubscriptionData using Effect
 * @internal - Do not call directly, use getUserSubscriptionData()
 */
async function getUserSubscriptionDataInternal(
  userId: string
): Promise<SubscriptionData> {
  "use cache: private";
  cacheTag(`user-${userId}`, "user-subscription");

  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  await cookies();

  const program = Effect.gen(function* () {
    const subscription = yield* SubscriptionService;
    const data = yield* subscription.getUserSubscriptionData(userId);
    return data;
  }).pipe(Effect.provide(SubscriptionLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return result;
  } catch (error: any) {
    logger.error("Failed to fetch subscription data:", error);
    // Return empty data on error (graceful degradation)
    return { subscription: null, profile: null };
  }
}

/**
 * Get user subscription data including profile for the authenticated user
 * - Uses React cache() for request deduplication, scoped by userId
 * - Automatically verifies user session matches provided userId
 * - Returns null values for missing data (graceful degradation)
 *
 * Promise wrapper around Effect-based SubscriptionService
 */
export const getUserSubscriptionData = cache(
  async (userId: string): Promise<SubscriptionData> => {
    const { user } = await verifySession();

    // SECURITY: Verify the provided userId matches the authenticated user
    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getUserSubscriptionDataInternal(userId);
  }
);

/**
 * Get subscription tier for a user.
 * Allows admin users to check any user's tier.
 *
 * @param userId - The user ID to check tier for
 */
export async function getUserTierById(userId: string): Promise<SubscriptionTier> {
  const { user } = await verifySession();

  // Allow if checking own tier OR if user is admin
  if (user.id !== userId) {
    const isAdmin = user.app_metadata?.role === "admin";
    if (!isAdmin) {
      throw new Error("Unauthorized - only admin can check other users' tier");
    }
  }

  // Use existing internal function
  const { subscription, profile } = await getUserSubscriptionDataInternal(userId);
  return getUserTier(subscription, profile);
}
