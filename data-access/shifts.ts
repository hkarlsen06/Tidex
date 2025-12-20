/**
 * Shifts Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * Uses ShiftsService for shift data access and payroll computations.
 *
 * Migration status: Using Effect-based ShiftsService internally
 */

import "server-only";
import { cache } from "react";
import { cacheTag } from "next/cache";
import { cookies } from "next/headers";
import { Effect } from "effect";
import { ShiftsService, type ShiftsAggregates, type PayoutTaxSettings } from "@/lib/services/shifts";
import { ShiftsLive } from "@/lib/layers/app";
import { logger } from "@/lib/logger";
import {
  type ShiftWithComputations,
  type UserSettings,
  PRESET_SUPPLEMENT_RULES,
} from "@/lib/payroll";
import { verifySession } from "@/data-access/auth";

export const PRESET_RULES = PRESET_SUPPLEMENT_RULES;

// Re-export types for backward compatibility
export type { ShiftsAggregates, PayoutTaxSettings };

export type ShiftLoadOptions = {
  startDate?: string; // YYYY-MM-DD
  endDate?: string; // YYYY-MM-DD
  limit?: number;
  /**
   * Year of the earnings month for payout tax calculation.
   * When both year and month are provided, the service will fetch
   * the tax settings from the payout month's snapshot.
   */
  year?: number;
  /**
   * Month (1-12) of the earnings month for payout tax calculation.
   * When both year and month are provided, the service will fetch
   * the tax settings from the payout month's snapshot.
   */
  month?: number;
};

/**
 * Internal implementation of getComputedShifts using Effect
 * @internal - Do not call directly, use getComputedShifts() or getComputedShiftsForApi()
 */
async function getComputedShiftsInternal(
  userId: string,
  options: ShiftLoadOptions = {}
): Promise<{
  shifts: ShiftWithComputations[];
  defaultView: string;
  settings: UserSettings;
  aggregates: ShiftsAggregates;
  payoutTaxSettings: PayoutTaxSettings;
}> {
  "use cache: private";
  cacheTag(`user-${userId}`, "user-shifts");

  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  await cookies();

  const program = Effect.gen(function* () {
    const shifts = yield* ShiftsService;
    const data = yield* shifts.getShiftsWithComputations({
      userId,
      startDate: options.startDate,
      endDate: options.endDate,
      limit: options.limit,
      year: options.year,
      month: options.month,
    });

    return data;
  }).pipe(
    Effect.provide(ShiftsLive),
    Effect.scoped
  );

  try {
    const result = await Effect.runPromise(program);
    // Convert readonly arrays to mutable for backward compatibility
    return {
      shifts: [...result.shifts],
      defaultView: result.defaultView,
      settings: result.settings,
      aggregates: result.aggregates,
      payoutTaxSettings: result.payoutTaxSettings,
    };
  } catch (error: any) {
    logger.error("Failed to fetch computed shifts:", error);
    // Return empty result on error for backward compatibility
    return {
      shifts: [],
      defaultView: "calendar",
      settings: {},
      aggregates: { totalHours: 0, totalEarnings: 0 },
      payoutTaxSettings: null,
    };
  }
}

/**
 * Get computed shifts with pagination and caching
 * - Uses React cache() for request deduplication within a single request
 * - Cache is scoped by userId to prevent cross-user data leaks
 * - Supports date range filtering and limits
 * - Automatically verifies user session matches provided userId
 * - Use this in Server Components and Server Actions
 *
 * Promise wrapper around Effect-based ShiftsService
 */
export const getComputedShifts = cache(
  async (
    userId: string,
    options: ShiftLoadOptions = {}
  ): Promise<{
    shifts: ShiftWithComputations[];
    defaultView: string;
    settings: UserSettings;
    aggregates: ShiftsAggregates;
    payoutTaxSettings: PayoutTaxSettings;
  }> => {
    const { user } = await verifySession();

    // SECURITY: Verify the provided userId matches the authenticated user
    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getComputedShiftsInternal(user.id, options);
  }
);

/**
 * Get computed shifts for API routes (no automatic auth)
 * - Requires manual authentication before calling
 * - Use this in API route handlers where redirect() is not supported
 * - Call getSession() first to verify auth, then pass user.id
 *
 * Promise wrapper around Effect-based ShiftsService
 */
export const getComputedShiftsForApi = cache(
  async (
    userId: string,
    options: ShiftLoadOptions = {}
  ): Promise<{
    shifts: ShiftWithComputations[];
    defaultView: string;
    settings: UserSettings;
    aggregates: ShiftsAggregates;
    payoutTaxSettings: PayoutTaxSettings;
  }> => {
    return getComputedShiftsInternal(userId, options);
  }
);
