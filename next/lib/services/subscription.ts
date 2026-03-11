/**
 * Subscription Service Layer
 *
 * Handles subscription and user profile data access with Effect-based error handling.
 * Integrates with Stripe via Supabase subscriptions table.
 */

import { Effect, Context, Layer } from "effect";
import { SupabaseService } from "./supabase";
import { AuthService } from "./auth";
import {
  DatabaseError,
  AuthError,
  NotFoundError,
  TimeoutError,
  SupabaseError,
} from "../errors/tagged";
import { logger } from "../logger";
import type { WageyInvocations } from "../wagey/types";

/**
 * Subscription record from database
 * Supports Stripe, Apple IAP, and admin trial providers via unified model
 */
export type Subscription = {
  readonly id: string;
  readonly user_id: string;
  // Provider identification
  readonly provider: 'stripe' | 'apple' | 'admin_trial';
  readonly provider_subscription_id: string | null;
  // Legacy Stripe fields (kept for backward compatibility)
  readonly stripe_customer_id: string | null;
  readonly stripe_subscription_id: string | null;
  // Unified subscription fields
  readonly status: string;
  readonly product_id: string | null;
  readonly current_period_start: string | null;
  readonly current_period_end: string | null;
  readonly created_at: string;
  readonly updated_at: string;
  readonly price_id: string | null;
  // Cancellation fields
  readonly cancel_at_period_end: boolean;
  readonly canceled_at: string | null;
  readonly cancel_at: string | null;
  readonly cancellation_reason: string | null;
  readonly cancellation_feedback: string | null;
  readonly cancellation_comment: string | null;
  // Apple IAP specific fields
  readonly apple_original_transaction_id: string | null;
  readonly apple_last_transaction_id: string | null;
  readonly apple_environment: 'Production' | 'Sandbox' | null;
  readonly app_account_token: string | null;
  // Localized price display (from App Store for Apple IAP)
  readonly price_display: string | null;
};

/**
 * User profile record from database
 */
export type UserProfile = {
  readonly id: string;
  readonly before_paywall: boolean;
  readonly wagey_invocations?: WageyInvocations | null;
  readonly created_at: string;
  readonly updated_at: string;
};

/**
 * Combined subscription and profile data
 */
export type SubscriptionData = {
  readonly subscription: Subscription | null;
  readonly profile: UserProfile | null;
};

/**
 * Subscription Service
 *
 * Provides access to user subscription data and profile information.
 * Returns null for missing subscriptions (free tier users).
 */
export class SubscriptionService extends Context.Tag("SubscriptionService")<
  SubscriptionService,
  {
    /**
     * Get user subscription by user ID
     * Returns null if user is on free plan (no subscription)
     */
    readonly getUserSubscription: (
      userId: string
    ) => Effect.Effect<
      Subscription | null,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get combined subscription and profile data
     * Returns null values for missing data (graceful degradation)
     */
    readonly getUserSubscriptionData: (
      userId: string,
      options?: { skipAuthCheck?: boolean }
    ) => Effect.Effect<
      SubscriptionData,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;
  }
>() {}

/**
 * Live implementation of SubscriptionService
 *
 * Requires: SupabaseService, AuthService
 */
export const SubscriptionServiceLive = Layer.effect(
  SubscriptionService,
  Effect.gen(function* () {
    const supabase = yield* SupabaseService;
    const auth = yield* AuthService;

    /**
     * Get user subscription
     * Returns null if no subscription exists (free tier)
     */
    const getUserSubscription = (userId: string) =>
      Effect.gen(function* () {
        // Verify user is authenticated
        yield* auth.verifyUserId(userId);

        // Query subscriptions table
        const result = yield* supabase.query(
          async (client) =>
            await client
              .from("subscriptions")
              .select("*")
              .eq("user_id", userId)
              .single(),
          { retries: 1 }
        );

        return result as unknown as Subscription;
      }).pipe(
        Effect.catchTag("DatabaseError", (error: DatabaseError) => {
          // Return null for missing subscriptions (PGRST116 - no data found)
          // Check both the error code and the cause's code for PGRST116 (Supabase "no rows" error)
          const causeCode = error.cause && typeof error.cause === "object" && "code" in error.cause
            ? (error.cause as { code?: string }).code
            : undefined;
          if (error.code === "NO_DATA" || causeCode === "PGRST116") {
            return Effect.succeed(null);
          }
          logger.error("Failed to fetch user subscription:", error);
          return Effect.fail(error);
        })
      );

    /**
     * Get combined subscription and profile data
     * Fetches both in parallel for efficiency
     */
    const getUserSubscriptionData = (
      userId: string,
      options?: { skipAuthCheck?: boolean }
    ) =>
      Effect.gen(function* () {
        if (!options?.skipAuthCheck) {
          yield* auth.verifyUserId(userId);
        }

        // Fetch subscription with graceful handling of not found
        const subscriptionEffect = supabase
          .query(
            async (client) =>
              await client
                .from("subscriptions")
                .select(`
                  id,
                  user_id,
                  provider,
                  provider_subscription_id,
                  stripe_customer_id,
                  stripe_subscription_id,
                  status,
                  product_id,
                  current_period_start,
                  current_period_end,
                  created_at,
                  updated_at,
                  price_id,
                  cancel_at_period_end,
                  canceled_at,
                  cancel_at,
                  cancellation_reason,
                  cancellation_feedback,
                  cancellation_comment,
                  apple_original_transaction_id,
                  apple_last_transaction_id,
                  apple_environment,
                  app_account_token,
                  price_display
                `)
                .eq("user_id", userId)
                .single(),
            { retries: 1 }
          )
          .pipe(
            Effect.map((result) => result as unknown as Subscription),
            Effect.catchTag("DatabaseError", (error: DatabaseError) => {
              // Check both the error code and the cause's code for PGRST116 (Supabase "no rows" error)
              const causeCode = error.cause && typeof error.cause === "object" && "code" in error.cause
                ? (error.cause as { code?: string }).code
                : undefined;
              if (error.code === "NO_DATA" || causeCode === "PGRST116") {
                return Effect.succeed(null);
              }
              logger.error("Failed to fetch user subscription:", error);
              return Effect.succeed(null); // Graceful degradation
            })
          );

        // Fetch profile with graceful handling of not found
        const profileEffect = supabase
          .query(
            async (client) =>
              await client
                .from("profiles")
                .select("id, before_paywall, wagey_invocations, created_at, updated_at")
                .eq("id", userId)
                .single(),
            { retries: 1 }
          )
          .pipe(
            Effect.map((result) => result as unknown as UserProfile),
            Effect.catchTag("DatabaseError", (error: DatabaseError) => {
              logger.error("Failed to fetch user profile:", error);
              return Effect.succeed(null); // Graceful degradation
            })
          );

        // Fetch both in parallel
        const [subscription, profile] = yield* Effect.all(
          [subscriptionEffect, profileEffect],
          { concurrency: 2 }
        );

        return { subscription, profile };
      });

    return {
      getUserSubscription,
      getUserSubscriptionData,
    };
  })
);
