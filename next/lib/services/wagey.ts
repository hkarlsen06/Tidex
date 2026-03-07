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
  type WageyTurnResult,
  WAGEY_LIMITS,
  getCurrentMonth,
  getResetDate,
} from "../wagey/types";
import type { SubscriptionData } from "./subscription";

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

    /**
     * Initialize a full Wagey chat turn in one request-scoped operation.
     * Verifies auth, resolves tier/usage, and consumes the invocation atomically.
     */
    readonly beginTurn: (
      userId: string
    ) => Effect.Effect<
      WageyTurnResult,
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

    const buildAccessResult = (subData: SubscriptionData): WageyAccessResult => {
      const level = getUserTier(subData.subscription, subData.profile);
      const limit = WAGEY_LIMITS[level];
      const hasAccess = level !== "free";
      const currentMonth = getCurrentMonth();
      const invocations = subData.profile?.wagey_invocations;
      const used = invocations?.month === currentMonth ? invocations.count : 0;
      const bonus = Math.max(0, invocations?.bonus ?? 0);
      const remaining = limit !== null ? Math.max(0, limit - used) : null;
      const resetDate = limit !== null ? getResetDate() : null;

      return {
        level,
        hasAccess,
        limit,
        used,
        remaining,
        bonus,
        resetDate,
      };
    };

    const runInvocationRpc = (
      userId: string,
      limit: number
    ): Effect.Effect<
      WageyInvocationResult,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    > =>
      Effect.gen(function* () {
        const currentMonth = getCurrentMonth();

        const rpcResult = yield* supabase.query(
          async (client) =>
            await client.rpc("increment_wagey_invocation", {
              p_user_id: userId,
              p_current_month: currentMonth,
              p_max_invocations: limit,
            }),
          { retries: 0 }
        );

        return rpcResult as unknown as WageyInvocationResult;
      });

    /**
     * Get user's Wagey access status
     */
    const getWageyAccess = (userId: string) =>
      Effect.gen(function* () {
        // Verify user is authenticated
        yield* auth.verifyUserId(userId);

        // Get subscription and profile data
        const subData = yield* subscription.getUserSubscriptionData(userId);
        return buildAccessResult(subData);
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
        const access = buildAccessResult(subData);
        const limit = access.limit ?? 0;
        const result = yield* runInvocationRpc(userId, limit);

        // Log result for debugging (use info level since debug doesn't exist)
        if (process.env.NODE_ENV === "development") {
          logger.info("Wagey invocation result:", {
            userId,
            level: access.level,
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
            bonus: 0,
          } satisfies WageyInvocationResult);
        })
      );

    const beginTurn = (userId: string) =>
      Effect.gen(function* () {
        yield* auth.verifyUserId(userId);

        const subData = yield* subscription.getUserSubscriptionData(userId);
        const access = buildAccessResult(subData);
        const limit = access.limit ?? 0;
        const invocation = yield* runInvocationRpc(userId, limit);

        if (process.env.NODE_ENV === "development") {
          logger.info("Wagey beginTurn result:", {
            userId,
            level: access.level,
            limit,
            invocation,
          });
        }

        return {
          access,
          invocation,
        } satisfies WageyTurnResult;
      });

    return {
      getWageyAccess,
      useInvocation,
      beginTurn,
    };
  })
);
