/**
 * Cache Management Layer
 *
 * Provides cache invalidation utilities using Next.js cache tags.
 * Now with Effect-based wrappers for composability.
 *
 * Uses revalidateTag for cache expiration (works in route handlers and server actions).
 */

import "server-only";
import { Effect } from "effect";
import { revalidateTag } from "next/cache";

/**
 * Invalidate all cached shift data for a user
 * Call this after creating, updating, or deleting a shift
 * Uses revalidateTag with "max" to immediately expire cache
 */
export function invalidateShiftsCache(userId: string): void {
  revalidateTag(`user-shifts-${userId}`, "max");
}

/**
 * Invalidate stats cache for a user
 * Call this after operations that affect stats calculations
 * Uses revalidateTag with "max" to immediately expire cache
 */
export function invalidateStatsCache(userId: string): void {
  revalidateTag(`user-stats-${userId}`, "max");
}

/**
 * Invalidate all user data caches
 * Call this after major operations like settings changes
 */
export function invalidateUserCache(userId: string): void {
  invalidateShiftsCache(userId);
  invalidateStatsCache(userId);
}

/**
 * Effect-based version of invalidateShiftsCache
 * Wraps side-effect in Effect.sync for composability
 *
 * @example
 * const program = Effect.gen(function* () {
 *   // ... database operations
 *   yield* invalidateShiftsCacheEffect(userId);
 * });
 */
export const invalidateShiftsCacheEffect = (userId: string) =>
  Effect.sync(() => revalidateTag(`user-shifts-${userId}`, "max"));

/**
 * Effect-based version of invalidateStatsCache
 *
 * @example
 * yield* invalidateStatsCacheEffect(userId);
 */
export const invalidateStatsCacheEffect = (userId: string) =>
  Effect.sync(() => revalidateTag(`user-stats-${userId}`, "max"));

/**
 * Effect-based version of invalidateUserCache
 * Invalidates all caches for a user in a single effect
 *
 * @example
 * const program = Effect.gen(function* () {
 *   // ... update user settings
 *   yield* invalidateUserCacheEffect(userId);
 * });
 */
export const invalidateUserCacheEffect = (userId: string) =>
  Effect.sync(() => invalidateUserCache(userId));

/**
 * Invalidate subscription cache for a user
 * Call this after subscription changes
 */
export function invalidateSubscriptionCache(userId: string): void {
  revalidateTag(`user-subscription-${userId}`, "max");
}

/**
 * Effect-based version of invalidateSubscriptionCache
 *
 * @example
 * yield* invalidateSubscriptionCacheEffect(userId);
 */
export const invalidateSubscriptionCacheEffect = (userId: string) =>
  Effect.sync(() => revalidateTag(`user-subscription-${userId}`, "max"));
