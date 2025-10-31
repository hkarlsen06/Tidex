/**
 * Cache revalidation utilities for Next.js
 *
 * Centralizes revalidation logic to ensure consistent cache invalidation
 * across all server actions that modify shift data.
 */

import { revalidatePath } from "next/cache";
import { invalidateUserCache } from "@/data-access/cache";

/**
 * Revalidates all pages that display shift data
 *
 * Call this after any shift modification to ensure the UI shows
 * updated data across all relevant pages.
 *
 * @example
 * export async function updateShift(id: string, data: ShiftData) {
 *   // ... update logic
 *   revalidateShiftData();
 *   return { success: true };
 * }
 */
export function revalidateShiftData() {
  // Use layout revalidation to ensure all localized routes are revalidated
  // This is more reliable than page-level revalidation for dynamic [locale] segments
  revalidatePath("/", "layout");
}

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
  // Use layout revalidation to ensure all localized routes are revalidated
  // This is more reliable than page-level revalidation for dynamic [locale] segments
  revalidatePath("/", "layout");
}
