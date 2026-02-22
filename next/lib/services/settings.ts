/**
 * Settings Service Layer
 *
 * Effect-based service for user settings and profile management with:
 * - Caching for performance
 * - Automatic authentication
 * - Typed error handling
 * - Security checks
 *
 * Usage:
 * ```typescript
 * const program = Effect.gen(function* () {
 *   const settings = yield* SettingsService
 *   const userSettings = yield* settings.getUserSettings(userId)
 *   return userSettings
 * }).pipe(
 *   Effect.provide(SettingsServiceLive)
 * )
 * ```
 */

import "server-only";
import { Context, Effect, Layer, Cache, Duration } from "effect";
import { AuthService } from "./auth";
import { SupabaseService } from "./supabase";
import { DatabaseError, AuthError, NotFoundError, TimeoutError, SupabaseError } from "../errors/tagged";
import type { SupplementRule } from "../payroll/types";

/**
 * Database user_settings row type
 * This is the complete type from the database, including display and payroll settings
 */
export type DbUserSettings = {
  user_id: string;
  theme?: string | null;
  default_shifts_view?: string | null;
  currency?: string | null;
  direct_time_input?: boolean | null;
  full_minute_range?: boolean | null;
  use_preset?: boolean | null;
  current_wage_level?: number | null;
  custom_wage?: number | null;
  custom_supplements?: { rules: SupplementRule[] } | null;
  pause_deduction_enabled?: boolean | null;
  pause_deduction_method?: string | null;
  pause_threshold_hours?: number | null;
  pause_deduction_minutes?: number | null;
  tax_deduction_enabled?: boolean | null;
  tax_percentage?: number | null;
  half_tax_month?: number | null;
  payroll_day?: number | null;
  monthly_goal?: number | null;
  monthly_goals_by_month?: Record<string, number> | null;
  profile_picture_url?: string | null;
  created_at?: string;
  updated_at?: string;
};

/**
 * User profile data with authentication methods
 */
export type UserProfile = {
  readonly firstName: string;
  readonly email: string;
  readonly profilePictureUrl: string | null;
  readonly hasGoogleConnected: boolean;
  readonly hasAppleConnected: boolean;
  readonly hasPhoneConnected: boolean;
  readonly phoneNumber: string | null;
  readonly hasPassword: boolean;
  readonly canUnlinkPhone: boolean;
  readonly canDisconnectGoogle: boolean;
  readonly canDisconnectApple: boolean;
  readonly isPhoneOnly: boolean;
  readonly isOAuthOnly: boolean;
};

/**
 * Settings Service Interface
 */
export class SettingsService extends Context.Tag("SettingsService")<
  SettingsService,
  {
    /**
     * Get user settings for authenticated user
     * Automatically verifies user ID matches authenticated user
     */
    readonly getUserSettings: (
      userId: string
    ) => Effect.Effect<
      DbUserSettings | null,
      DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError,
      never
    >;

    /**
     * Get user profile information
     * Includes authentication methods and connection status
     */
    readonly getUserProfile: (
      userId: string
    ) => Effect.Effect<UserProfile, DatabaseError | AuthError | NotFoundError | TimeoutError | SupabaseError, never>;
  }
>() {}

/**
 * Live implementation of SettingsService
 *
 * Uses Effect Cache for settings/profile caching
 */
export const SettingsServiceLive = Layer.effect(
  SettingsService,
  Effect.gen(function* () {
    const auth = yield* AuthService;
    const supabase = yield* SupabaseService;

    // Create cache for user settings (10 minute TTL)
    const settingsCache = yield* Cache.make({
      capacity: 100,
      timeToLive: Duration.minutes(10),
      lookup: (userId: string) =>
        Effect.gen(function* () {
          // Verify user ID matches authenticated user (security check)
          yield* auth.verifyUserId(userId);

          // Query user settings - use maybeSingle() to return null if no rows
          const result = yield* supabase.query(
            async (client) =>
              await client
                .from("user_settings")
                .select("*")
                .eq("user_id", userId)
                .maybeSingle(),
            { retries: 2 }
          );

          return result as DbUserSettings | null;
        }),
    });

    // Create cache for user profile (5 minute TTL)
    const profileCache = yield* Cache.make({
      capacity: 100,
      timeToLive: Duration.minutes(5),
      lookup: (userId: string) =>
        Effect.gen(function* () {
          // Verify user is authenticated first
          const session = yield* auth.getSession();

          if (session.user.id !== userId) {
            return yield* Effect.fail(
              new AuthError({
                reason: "unauthorized",
                cause: new Error("User ID mismatch - potential security violation"),
              })
            );
          }

          // IMPORTANT: Fetch fresh user data from Supabase to get accurate identity info.
          // The JWT claims (app_metadata.providers) can be stale after linking/unlinking.
          // The identities array from getUser() is the source of truth.
          const client = yield* supabase.getClient();
          const { data: freshUserData, error: freshUserError } = yield* Effect.tryPromise({
            try: () => client.auth.getUser(),
            catch: (error) =>
              new SupabaseError({
                operation: "getUser",
                cause: error,
              }),
          });

          if (freshUserError || !freshUserData.user) {
            return yield* Effect.fail(
              new NotFoundError({
                resource: "User",
              })
            );
          }

          const freshUser = freshUserData.user;

          // Get profile picture from settings
          const settingsResult = yield* supabase
            .query(
              async (client) =>
                await client
                  .from("user_settings")
                  .select("profile_picture_url")
                  .eq("user_id", userId)
                  .single(),
              { retries: 2 }
            )
            .pipe(
              Effect.catchTag("DatabaseError", () =>
                Effect.succeed({ profile_picture_url: null })
              )
            );

          // Extract identity providers from fresh user data (source of truth)
          const identities = freshUser.identities ?? [];
          const identityProviders = new Set(
            identities.map((i: { provider: string }) => i.provider)
          );

          const hasGoogleConnected = identityProviders.has("google");
          const hasAppleConnected = identityProviders.has("apple");
          const hasPhoneConnected = identityProviders.has("phone");
          const metadataHasPassword = Boolean(
            (freshUser.user_metadata as { hasPassword?: boolean } | null | undefined)
              ?.hasPassword
          );
          const hasPassword = identityProviders.has("email") || metadataHasPassword;

          // Format phone number (strip +47 prefix for display)
          let phoneNumber: string | null = null;
          if (freshUser.phone) {
            phoneNumber = freshUser.phone.startsWith("+47")
              ? freshUser.phone.substring(3)
              : freshUser.phone;
          }

          // Calculate connection capabilities
          const passwordCountsAsMethod = hasPassword && Boolean(freshUser.email);
          const loginMethodCount =
            identityProviders.size + (passwordCountsAsMethod && !identityProviders.has("email") ? 1 : 0);
          const canUnlinkPhone = hasPhoneConnected && loginMethodCount > 1;
          const canDisconnectGoogle = hasGoogleConnected && loginMethodCount > 1;
          const canDisconnectApple = hasAppleConnected && loginMethodCount > 1;
          const isPhoneOnly = hasPhoneConnected && !freshUser.email;
          // User is OAuth-only if they have OAuth but no password and no phone
          const isOAuthOnly =
            (hasGoogleConnected || hasAppleConnected) &&
            !hasPassword &&
            !hasPhoneConnected;

          const profile: UserProfile = {
            firstName: (freshUser.user_metadata?.full_name as string) ?? "",
            email: freshUser.email ?? "",
            profilePictureUrl:
              (settingsResult as { profile_picture_url: string | null })
                ?.profile_picture_url ?? null,
            hasGoogleConnected,
            hasAppleConnected,
            hasPhoneConnected,
            phoneNumber,
            hasPassword,
            canUnlinkPhone,
            canDisconnectGoogle,
            canDisconnectApple,
            isPhoneOnly,
            isOAuthOnly,
          };

          return profile;
        }),
    });

    return {
      /**
       * Get user settings with caching
       */
      getUserSettings: (userId: string) => settingsCache.get(userId),

      /**
       * Get user profile with caching
       */
      getUserProfile: (userId: string) => profileCache.get(userId),
    };
  })
);

/**
 * Convenience function to provide SettingsServiceLive with dependencies
 */
export const withSettings = <A, E, R>(
  effect: Effect.Effect<A, E, R | SettingsService>
): Effect.Effect<A, E, Exclude<R, SettingsService> | AuthService | SupabaseService> =>
  Effect.provide(effect, SettingsServiceLive);
