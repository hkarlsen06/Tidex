import "server-only";
import { updateTag } from "next/cache";

/**
 * Invalidate all cached shift data for a user
 * Call this after creating, updating, or deleting a shift
 * Uses updateTag for immediate cache expiration (read-your-own-writes)
 */
export function invalidateShiftsCache(userId: string): void {
  updateTag(`user-shifts-${userId}`);
}

/**
 * Invalidate stats cache for a user
 * Call this after operations that affect stats calculations
 * Uses updateTag for immediate cache expiration (read-your-own-writes)
 */
export function invalidateStatsCache(userId: string): void {
  updateTag(`user-stats-${userId}`);
}

/**
 * Invalidate all user data caches
 * Call this after major operations like settings changes
 */
export function invalidateUserCache(userId: string): void {
  invalidateShiftsCache(userId);
  invalidateStatsCache(userId);
}
