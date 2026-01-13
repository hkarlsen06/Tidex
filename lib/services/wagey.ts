/**
 * Wagey Service Layer
 *
 * Handles Wagey AI assistant access control and usage tracking.
 * Effect-based service with atomic increment via Supabase RPC.
 */

import { Effect, Context, Layer } from "effect";
import { SupabaseService } from "./supabase";
import { AuthService } from "./auth";
import { SubscriptionService } from "./subscription";
import {
  DatabaseError,
  AuthError,
  NotFoundError,
  TimeoutError,
  SupabaseError,
} from "../errors/tagged";
import { logger } from "../logger";
import { getUserTier } from "../subscription/getUserTier";
import {
  type WageyAccessResult,
  type WageyInvocationResult,
  type WageyInvocations,
  WAGEY_LIMITS,
  getCurrentMonth,
  getResetDate,
} from "../wagey/types";

/**
 * Profile with wagey_invocations for internal use
 */
type ProfileWithInvocations = {
  readonly id: string;
  readonly before_paywall: boolean;
  readonly wagey_invocations: WageyInvocations | null;
};

/**
 * Wagey Service
 *
 * Provides access control and usage tracking for Wagey AI assistant.
 */
export class WageyService extends Context.Tag("WageyService")<
  WageyService,
  {
    /**
     * Get user's Wagey access status including usage counts
     */
    readonly getWageyAccess: (
      userId: string
    ) => Effect.Effect<
      WageyAccessResult,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Attempt to use a Wagey invocation
     * Atomically increments the counter if allowed
     * Returns whether the invocation was permitted
     */
    readonly useInvocation: (
      userId: string
    ) => Effect.Effect<
      WageyInvocationResult,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;
  }
>() {}

/**
 * Live implementation of WageyService
 *
 * Requires: SupabaseService, AuthService, SubscriptionService
 */
export const WageyServiceLive = Layer.effect(
  WageyService,
  Effect.gen(function* () {
    const supabase = yield* SupabaseService;
    const auth = yield* AuthService;
    const subscription = yield* SubscriptionService;

    /**
     * Get user's Wagey access status
     */
    const getWageyAccess = (userId: string) =>
      Effect.gen(function* () {
        // Verify user is authenticated
        yield* auth.verifyUserId(userId);

        // Get subscription and profile data
        const subData = yield* subscription.getUserSubscriptionData(userId);

        // Determine access level
        const level = getUserTier(subData.subscription, subData.profile);
        const limit = WAGEY_LIMITS[level];
        const hasAccess = level !== "free";

        // Get current usage from profile
        const currentMonth = getCurrentMonth();
        let used = 0;

        // Fetch profile with wagey_invocations
        const profileResult = yield* supabase
          .query(
            async (client) =>
              await client
                .from("profiles")
                .select("id, before_paywall, wagey_invocations")
                .eq("id", userId)
                .single(),
            { retries: 1 }
          )
          .pipe(
            Effect.map((result) => result as unknown as ProfileWithInvocations),
            Effect.catchTag("DatabaseError", () => Effect.succeed(null))
          );

        if (profileResult?.wagey_invocations) {
          const invocations = profileResult.wagey_invocations;
          // Only count if same month, otherwise reset is pending
          if (invocations.month === currentMonth) {
            used = invocations.count;
          }
        }

        const remaining = limit !== null ? Math.max(0, limit - used) : null;
        const resetDate = limit !== null ? getResetDate() : null;

        return {
          level,
          hasAccess,
          limit,
          used,
          remaining,
          resetDate,
        } satisfies WageyAccessResult;
      });

    /**
     * Attempt to use a Wagey invocation
     * Uses atomic RPC function for race-condition safety
     */
    const useInvocation = (userId: string) =>
      Effect.gen(function* () {
        // Verify user is authenticated
        yield* auth.verifyUserId(userId);

        // Get subscription data to determine limit
        const subData = yield* subscription.getUserSubscriptionData(userId);
        const level = getUserTier(subData.subscription, subData.profile);

        // Get limit for user's tier (free users get trial limit)
        const limit = WAGEY_LIMITS[level];
        const currentMonth = getCurrentMonth();

        const rpcResult = yield* supabase.query(
          async (client) =>
            await client.rpc("increment_wagey_invocation", {
              p_user_id: userId,
              p_current_month: currentMonth,
              p_max_invocations: limit,
            }),
          { retries: 0 } // No retries for atomic operations
        );

        // RPC returns JSONB with { allowed, count, remaining }
        const result = rpcResult as unknown as WageyInvocationResult;

        // Log result for debugging (use info level since debug doesn't exist)
        if (process.env.NODE_ENV === "development") {
          logger.info("Wagey invocation result:", {
            userId,
            level,
            limit,
            result,
          });
        }

        return result;
      }).pipe(
        Effect.catchTag("DatabaseError", (error: DatabaseError) => {
          logger.error("Failed to use Wagey invocation:", error);
          // On error, deny the request to be safe
          return Effect.succeed({
            allowed: false,
            count: 0,
            remaining: 0,
          } satisfies WageyInvocationResult);
        })
      );

    return {
      getWageyAccess,
      useInvocation,
    };
  })
);
