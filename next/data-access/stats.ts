/**
 * Stats Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * Uses StatsService for comprehensive statistics and analytics.
 *
 * Migration status: Using Effect-based StatsService internally
 */

import "server-only";
import { cache } from "react";
import { cacheTag } from "next/cache";
import { cookies } from "next/headers";
import { Effect } from "effect";
import {
  StatsService,
  type StatsData,
  type MonthlyTotal,
  type CriticalStatsData,
  type MonthlyData,
  type DailyData,
  type DailyCumulativeData,
  type YearlyCumulativeData,
  type MonthlySummary,
  type SupplementBreakdown,
  type MonthlyGoal,
  type EmploymentMonthlyData,
  type BestWeekData,
} from "@/lib/services/stats";
import { StatsLive } from "@/lib/layers/app";
import { logger } from "@/lib/logger";
import { verifySession } from "@/data-access/auth";
import type { Locale } from "@/lib/i18n/config";

// Re-export types for backward compatibility
export type {
  StatsData,
  MonthlyTotal,
  CriticalStatsData,
  MonthlyData,
  DailyData,
  DailyCumulativeData,
  YearlyCumulativeData,
  MonthlySummary,
  SupplementBreakdown,
  MonthlyGoal,
  EmploymentMonthlyData,
  BestWeekData,
};

export type StatsOptions = {
  year?: number;
  month?: number; // 1-12
  locale?: Locale;
};

/**
 * Internal implementation of getMonthlyTotal using Effect
 * @internal - Do not call directly, use getMonthlyTotal()
 */
async function getMonthlyTotalInternal(userId: string): Promise<MonthlyTotal> {
  "use cache: private";
  cacheTag(`user-${userId}`, "user-stats");

  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  await cookies();

  const program = Effect.gen(function* () {
    const stats = yield* StatsService;
    const data = yield* stats.getMonthlyTotal(userId);
    return data;
  }).pipe(Effect.provide(StatsLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return result;
  } catch (error: any) {
    logger.error("Failed to fetch monthly total:", error);
    // Return empty result on error for backward compatibility
    return {
      total: "0 kr",
      tillegg: "0 kr",
      gross: 0,
      supplementPay: 0,
      shiftCount: 0,
      earnedToDate: "0 kr",
      earnedToDateGross: 0,
    };
  }
}

/**
 * Get the current month's total gross earnings for a user with comparison to last month
 * - Uses React cache() for request deduplication, scoped by userId
 * - Automatically verifies user session matches provided userId
 *
 * Promise wrapper around Effect-based StatsService
 */
export const getMonthlyTotal = cache(async (userId: string): Promise<MonthlyTotal> => {
  const { user } = await verifySession();

  // SECURITY: Verify the provided userId matches the authenticated user
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  return getMonthlyTotalInternal(userId);
});

/**
 * Internal implementation of getStatsData using Effect
 * @internal - Do not call directly, use getStatsData() or getStatsDataForApi()
 */
async function getStatsDataInternal(userId: string, options: StatsOptions = {}): Promise<StatsData> {
  "use cache: private";
  cacheTag(`user-${userId}`, "user-stats");

  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  await cookies();

  const program = Effect.gen(function* () {
    const stats = yield* StatsService;
    const data = yield* stats.getStatsData({
      userId,
      year: options.year,
      month: options.month,
      locale: options.locale || "no",
    });
    return data;
  }).pipe(Effect.provide(StatsLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    // Convert readonly arrays to mutable for backward compatibility
    return {
      ...result,
      yearlyMonths: [...result.yearlyMonths],
      thisWeek: [...result.thisWeek],
      bestWeek: result.bestWeek ? {
        ...result.bestWeek,
        weekData: [...result.bestWeek.weekData],
      } : null,
      thisMonthCumulative: [...result.thisMonthCumulative],
      yearlyCumulative: [...result.yearlyCumulative],
      monthlySummaries: [...result.monthlySummaries],
      employmentLast6Months: [...result.employmentLast6Months],
    };
  } catch (error: any) {
    logger.error("Failed to fetch stats data:", error);
    // Return empty result on error for backward compatibility
    return {
      focusMonth: {
        year: new Date().getUTCFullYear(),
        month: new Date().getUTCMonth() + 1,
      },
      tax: {
        enabled: false,
        percentage: 0,
      },
      currentMonth: {
        totalEarnings: 0,
        totalEarningsNet: 0,
        totalHours: 0,
        shiftCount: 0,
        averageRate: 0,
      },
      lastMonth: {
        totalEarnings: 0,
        totalEarningsNet: 0,
        totalHours: 0,
        shiftCount: 0,
      },
      percentageChange: null,
      yearToDate: {
        totalEarnings: 0,
        totalHours: 0,
        shiftCount: 0,
      },
      fullYear: {
        totalEarnings: 0,
        totalHours: 0,
        shiftCount: 0,
      },
      yearlyMonths: [],
      thisWeek: [],
      bestWeek: null,
      thisMonthCumulative: [],
      yearlyCumulative: [],
      monthlySummaries: [],
      currentMonthBreakdown: {
        basePay: 0,
        supplementPay: 0,
        basePercentage: 0,
        supplementPercentage: 0,
      },
      monthlyGoal: {
        enabled: false,
        target: 0,
        progress: 0,
        percentage: 0,
        remaining: 0,
      },
      employmentLast6Months: [],
      employmentYearlyAverage: null,
    };
  }
}

/**
 * Get comprehensive stats data with caching
 * - Uses React cache() for request deduplication, scoped by userId
 * - Includes monthly summaries, charts data, and projections
 * - Automatically verifies user session matches provided userId
 * - Use this in Server Components and Server Actions
 *
 * Promise wrapper around Effect-based StatsService
 */
export const getStatsData = cache(async (userId: string, options: StatsOptions = {}): Promise<StatsData> => {
  const { user } = await verifySession();

  // SECURITY: Verify the provided userId matches the authenticated user
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  return getStatsDataInternal(userId, options);
});

/**
 * Get stats data for API routes (no automatic auth)
 * - Requires manual authentication before calling
 * - Use this in API route handlers where redirect() is not supported
 * - Call getSession() first to verify auth
 *
 * Promise wrapper around Effect-based StatsService
 */
export const getStatsDataForApi = cache(async (userId: string, options: StatsOptions = {}): Promise<StatsData> => {
  return getStatsDataInternal(userId, options);
});

/**
 * Get only critical stats data for initial page render
 * - Loads only essential current month stats
 * - Much faster than full stats data
 * - Charts data loaded separately via API
 * - Automatically verifies user session matches provided userId
 *
 * Promise wrapper around Effect-based StatsService
 */
export const getCriticalStatsData = cache(async (userId: string, options: StatsOptions = {}): Promise<CriticalStatsData> => {
  const { user } = await verifySession();

  // SECURITY: Verify the provided userId matches the authenticated user
  if (user.id !== userId) {
    throw new Error("User ID mismatch - potential security violation");
  }

  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  await cookies();

  const program = Effect.gen(function* () {
    const stats = yield* StatsService;
    const data = yield* stats.getCriticalStatsData({
      userId,
      year: options.year,
      month: options.month,
      locale: options.locale || "no",
    });
    return data;
  }).pipe(Effect.provide(StatsLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return result;
  } catch (error: any) {
    logger.error("Failed to fetch critical stats data:", error);
    // Return empty result on error for backward compatibility
    return {
      focusMonth: {
        year: new Date().getUTCFullYear(),
        month: new Date().getUTCMonth() + 1,
      },
      tax: {
        enabled: false,
        percentage: 0,
      },
      currentMonth: {
        totalEarnings: 0,
        totalEarningsNet: 0,
        totalHours: 0,
        shiftCount: 0,
        averageRate: 0,
      },
      lastMonth: {
        totalEarnings: 0,
        totalEarningsNet: 0,
        totalHours: 0,
        shiftCount: 0,
      },
      percentageChange: null,
      monthlyGoal: {
        enabled: false,
        target: 0,
        progress: 0,
        percentage: 0,
        remaining: 0,
      },
    };
  }
});
