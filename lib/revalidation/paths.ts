/**
 * Cache revalidation utilities for Next.js
 *
 * Centralizes revalidation logic to ensure consistent cache invalidation
 * across all server actions that modify shift data.
 */

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
