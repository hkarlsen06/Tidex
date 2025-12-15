/**
 * Sharing Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * Uses SharingService for shift sharing data access.
 *
 * Migration status: Using Effect-based SharingService internally
 */

import "server-only";
import { cache } from "react";
import { cacheTag } from "next/cache";
import { cookies } from "next/headers";
import { Effect } from "effect";
import {
  SharingService,
  type SharedUser,
  type ShareRecipient,
} from "@/lib/services/sharing";
import { SharingLive, ShiftsLive } from "@/lib/layers/app";
import { ShiftsService } from "@/lib/services/shifts";
import { logger } from "@/lib/logger";
import { verifySession } from "@/data-access/auth";
import type { ShiftWithComputations, UserSettings } from "@/lib/payroll";
import type { ShiftsAggregates } from "@/lib/services/shifts";

// Re-export types for backward compatibility
export type { SharedUser, ShareRecipient };

/**
 * Internal implementation of getUsersWhoSharedWithMe
 * @internal - Do not call directly, use getUsersWhoSharedWithMe()
 */
async function getUsersWhoSharedWithMeInternal(
  userId: string
): Promise<SharedUser[]> {
  "use cache: private";
  cacheTag(`user-${userId}`, "sharing-received");

  await cookies();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    const data = yield* sharing.getUsersWhoSharedWithMe(userId);
    return data;
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return [...result];
  } catch (error: any) {
    logger.error("Failed to fetch users who shared with me:", error);
    return [];
  }
}

/**
 * Get users who have shared their shifts with the current user
 * - Uses React cache() for request deduplication
 * - Cache is scoped by userId
 *
 * Promise wrapper around Effect-based SharingService
 */
export const getUsersWhoSharedWithMe = cache(
  async (userId: string): Promise<SharedUser[]> => {
    const { user } = await verifySession();

    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getUsersWhoSharedWithMeInternal(userId);
  }
);

/**
 * Internal implementation of getMyShareRecipients
 * @internal - Do not call directly, use getMyShareRecipients()
 */
async function getMyShareRecipientsInternal(
  userId: string
): Promise<ShareRecipient[]> {
  "use cache: private";
  cacheTag(`user-${userId}`, "sharing-given");

  await cookies();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    const data = yield* sharing.getMyShareRecipients(userId);
    return data;
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return [...result];
  } catch (error: any) {
    logger.error("Failed to fetch my share recipients:", error);
    return [];
  }
}

/**
 * Get users the current user has shared their shifts with
 * - Uses React cache() for request deduplication
 * - Cache is scoped by userId
 *
 * Promise wrapper around Effect-based SharingService
 */
export const getMyShareRecipients = cache(
  async (userId: string): Promise<ShareRecipient[]> => {
    const { user } = await verifySession();

    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getMyShareRecipientsInternal(userId);
  }
);

/**
 * Strip earnings data from a shift, keeping only hours-related fields
 * Used when showEarnings is false for a share relationship
 *
 * Structure: ShiftWithComputations = ShiftRow & { computed: ShiftComputed }
 * - computed contains: gross, basePay, supplementPay, wagePeriods
 * We zero out monetary values while preserving hour data
 */
function stripEarningsFromShift(shift: ShiftWithComputations): ShiftWithComputations {
  return {
    ...shift,
    // Zero out the computed earnings fields
    computed: {
      ...shift.computed,
      basePay: 0,
      supplementPay: 0,
      gross: 0,
      // Clear wage periods to hide supplement breakdown
      wagePeriods: [],
      originalWagePeriods: [],
    },
    // Clear tax info
    tax_enabled: undefined,
    tax_percentage: undefined,
  };
}

/**
 * Aggregates for shared shifts (earnings may be hidden)
 */
export type SharedShiftsAggregates = {
  totalHours: number;
  totalEarnings: number | null; // null when showEarnings is false
};

/**
 * Internal implementation of getSharedUserShifts
 * @internal - Do not call directly, use getSharedUserShifts()
 */
async function getSharedUserShiftsInternal(
  viewerId: string,
  ownerId: string,
  options: { startDate?: string; endDate?: string; limit?: number } = {}
): Promise<{
  shifts: ShiftWithComputations[];
  defaultView: string;
  settings: UserSettings;
  aggregates: SharedShiftsAggregates;
  showEarnings: boolean;
}> {
  "use cache: private";
  cacheTag(`user-${ownerId}`, "shared-shifts");

  await cookies();

  // First verify the viewer has access and get share settings
  const shareSettingsProgram = Effect.gen(function* () {
    const sharing = yield* SharingService;
    return yield* sharing.getShareSettings(viewerId, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  const shareSettings = await Effect.runPromise(shareSettingsProgram);

  if (!shareSettings) {
    logger.warn(`User ${viewerId} attempted to access shifts of ${ownerId} without permission`);
    return {
      shifts: [],
      defaultView: "calendar",
      settings: {},
      aggregates: { totalHours: 0, totalEarnings: null },
      showEarnings: false,
    };
  }

  const showEarnings = shareSettings.showEarnings;

  // Now fetch the shifts using the owner's ID (since RLS allows it through shift_shares)
  // We skip auth check because we've already verified share access above
  const program = Effect.gen(function* () {
    const shifts = yield* ShiftsService;
    const data = yield* shifts.getShiftsWithComputations({
      userId: ownerId,
      startDate: options.startDate,
      endDate: options.endDate,
      limit: options.limit,
      skipAuthCheck: true, // Access already verified via getShareSettings
    });
    return data;
  }).pipe(Effect.provide(ShiftsLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);

    // SECURITY: If showEarnings is false, strip all earnings data server-side
    // This is the security enforcement point - data is filtered before reaching the client
    if (!showEarnings) {
      return {
        shifts: result.shifts.map(stripEarningsFromShift),
        defaultView: result.defaultView,
        settings: {
          ...result.settings,
          // Optionally hide wage-related settings too
        },
        aggregates: {
          totalHours: result.aggregates.totalHours,
          totalEarnings: null, // Hide total earnings
        },
        showEarnings: false,
      };
    }

    return {
      shifts: [...result.shifts],
      defaultView: result.defaultView,
      settings: result.settings,
      aggregates: result.aggregates,
      showEarnings: true,
    };
  } catch (error: any) {
    logger.error("Failed to fetch shared user shifts:", error);
    return {
      shifts: [],
      defaultView: "calendar",
      settings: {},
      aggregates: { totalHours: 0, totalEarnings: null },
      showEarnings: false,
    };
  }
}

/**
 * Get computed shifts for a user who has shared their shifts with the viewer
 * - Verifies viewer has share access before returning data
 * - Filters out earnings data if showEarnings is false (security enforcement)
 * - Uses React cache() for request deduplication
 *
 * Promise wrapper around Effect-based services
 */
export const getSharedUserShifts = cache(
  async (
    ownerId: string,
    options: { startDate?: string; endDate?: string; limit?: number } = {}
  ): Promise<{
    shifts: ShiftWithComputations[];
    defaultView: string;
    settings: UserSettings;
    aggregates: SharedShiftsAggregates;
    showEarnings: boolean;
  }> => {
    const { user } = await verifySession();

    return getSharedUserShiftsInternal(user.id, ownerId, options);
  }
);

/**
 * Update share settings for a specific recipient
 * - Only the owner can update settings for their shares
 * - Used to toggle earnings visibility
 *
 * Promise wrapper around Effect-based SharingService
 */
export async function updateShareSettings(
  recipientId: string,
  settings: { showEarnings: boolean }
): Promise<{ success: boolean; error?: string }> {
  const { user } = await verifySession();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.updateShareSettings(user.id, recipientId, settings);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);
    return { success: true };
  } catch (error: any) {
    logger.error("Failed to update share settings:", error);
    return { success: false, error: "Failed to update share settings" };
  }
}

/**
 * Check if the current user can add more share recipients
 * - Based on subscription tier limits
 */
export const canAddMoreRecipients = cache(
  async (
    userId: string
  ): Promise<{ canAdd: boolean; currentCount: number; limit: number }> => {
    const { user } = await verifySession();

    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    const program = Effect.gen(function* () {
      const sharing = yield* SharingService;
      return yield* sharing.canAddMoreRecipients(userId);
    }).pipe(Effect.provide(SharingLive), Effect.scoped);

    try {
      return await Effect.runPromise(program);
    } catch (error: any) {
      logger.error("Failed to check share capacity:", error);
      return { canAdd: false, currentCount: 0, limit: 0 };
    }
  }
);
