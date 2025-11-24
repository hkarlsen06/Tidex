/**
 * Cache Management Layer
 *
 * Provides cache invalidation utilities using Next.js cache tags.
 * Now with Effect-based wrappers for composability.
 *
 * Uses revalidateTag for cache expiration (works in route handlers and server actions).
 *
 * IMPORTANT: Cache tags must match those set in DAL functions using cacheTag().
 * DAL functions use: cacheTag(`user-${userId}`, "category-name")
 * This sets TWO tags: `user-${userId}` and "category-name"
 * To invalidate, we use the per-user tag: `user-${userId}`
 */

import "server-only";
import { Effect } from "effect";
import { revalidateTag } from "next/cache";

/**
 * Invalidate all cached data for a user
 * This invalidates shifts, stats, settings, subscription, and all other user data
 * Call this after creating, updating, or deleting any user data
 * Uses revalidateTag with "max" to immediately expire cache
 */
export function invalidateUserCache(userId: string): void {
  revalidateTag(`user-${userId}`, "max");
}

/**
 * Invalidate all cached shift data for a user
 * Alias for invalidateUserCache for backward compatibility
 * @deprecated Use invalidateUserCache instead
 */
export function invalidateShiftsCache(userId: string): void {
  invalidateUserCache(userId);
}

/**
 * Invalidate stats cache for a user
 * Alias for invalidateUserCache for backward compatibility
 * @deprecated Use invalidateUserCache instead
 */
export function invalidateStatsCache(userId: string): void {
  invalidateUserCache(userId);
}

/**
 * Invalidate subscription cache for a user
 * Alias for invalidateUserCache for backward compatibility
 * @deprecated Use invalidateUserCache instead
 */
export function invalidateSubscriptionCache(userId: string): void {
  invalidateUserCache(userId);
}

/**
 * Effect-based version of invalidateUserCache
 * Wraps side-effect in Effect.sync for composability
 *
 * @example
 * const program = Effect.gen(function* () {
 *   // ... database operations
 *   yield* invalidateUserCacheEffect(userId);
 * });
 */
export const invalidateUserCacheEffect = (userId: string) =>
  Effect.sync(() => revalidateTag(`user-${userId}`, "max"));

/**
 * Effect-based version of invalidateShiftsCache
 * Alias for backward compatibility
 * @deprecated Use invalidateUserCacheEffect instead
 */
export const invalidateShiftsCacheEffect = (userId: string) =>
  invalidateUserCacheEffect(userId);

/**
 * Effect-based version of invalidateStatsCache
 * Alias for backward compatibility
 * @deprecated Use invalidateUserCacheEffect instead
 */
export const invalidateStatsCacheEffect = (userId: string) =>
  invalidateUserCacheEffect(userId);

/**
 * Effect-based version of invalidateSubscriptionCache
 * Alias for backward compatibility
 * @deprecated Use invalidateUserCacheEffect instead
 */
export const invalidateSubscriptionCacheEffect = (userId: string) =>
  invalidateUserCacheEffect(userId);
