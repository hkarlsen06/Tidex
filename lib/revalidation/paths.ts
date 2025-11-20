/**
 * Cache revalidation utilities for Next.js
 *
 * Centralizes revalidation logic to ensure consistent cache invalidation
 * across all server actions that modify shift data.
 *
 * Now with Effect-based wrappers for composability.
 */

import { Effect } from "effect";
import { revalidatePath } from "next/cache";
import { invalidateUserCache } from "@/data-access/cache";

/**
 * Invalidates user cache and revalidates all shift-related pages
 *
 * Use this after any data modification for a user. This combines cache
 * invalidation (for server-side cached data) with path revalidation
 * (for Next.js page cache).
 *
 * @param userId - The ID of the user whose cache should be invalidated
 *
 * @example
 * export async function deleteShift(id: string) {
 *   const user = await verifySession();
 *   // ... delete logic
 *   invalidateAndRevalidate(user.id);
 *   return { success: true };
 * }
 */
export function invalidateAndRevalidate(userId: string) {
  invalidateUserCache(userId);
  revalidatePath("/", "layout");
}

/**
 * Effect-based version of invalidateAndRevalidate
 * Wraps side-effects in Effect.sync for composability
 *
 * @example
 * const program = Effect.gen(function* () {
 *   // ... perform database operations
 *   yield* invalidateAndRevalidateEffect(userId);
 *   return { success: true };
 * });
 */
export const invalidateAndRevalidateEffect = (userId: string) =>
  Effect.sync(() => {
    invalidateUserCache(userId);
    revalidatePath("/", "layout");
  });

/**
 * Revalidate a specific path
 * Effect-based wrapper for Next.js revalidatePath
 *
 * @example
 * yield* revalidatePathEffect("/shifts");
 */
export const revalidatePathEffect = (
  path: string,
  type?: "page" | "layout"
) =>
  Effect.sync(() => {
    revalidatePath(path, type);
  });

/**
 * Invalidate user cache only (no path revalidation)
 * Effect-based wrapper
 *
 * @example
 * yield* invalidateUserCacheEffect(userId);
 */
export const invalidateUserCacheEffect = (userId: string) =>
  Effect.sync(() => {
    invalidateUserCache(userId);
  });
