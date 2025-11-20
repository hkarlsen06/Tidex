/**
 * Authentication Service Layer
 *
 * Effect-based authentication service with:
 * - Session verification with caching
 * - Typed error handling (no redirect throws)
 * - User identity management
 * - Composable with other services
 *
 * Usage:
 * ```typescript
 * const program = Effect.gen(function* () {
 *   const auth = yield* AuthService
 *   const user = yield* auth.getCurrentUser()
 *   return user
 * }).pipe(
 *   Effect.provide(AuthServiceLive)
 * )
 * ```
 */

import "server-only";
import { Context, Effect, Layer, Cache, Duration } from "effect";
import type { User } from "@supabase/supabase-js";
import { AuthError, NotFoundError } from "../errors/tagged";
import { SupabaseService } from "./supabase";

/**
 * User identity information
 */
export type UserIdentity = {
  readonly id: string;
  readonly email: string | null;
  readonly phone: string | null;
  readonly firstName: string | null;
  readonly metadata: Record<string, unknown>;
  readonly identityProviders: ReadonlySet<string>;
};

/**
 * Session data
 */
export type SessionData = {
  readonly user: UserIdentity;
  readonly rawUser: User; // For backward compatibility
};

/**
 * Authentication Service Interface
 */
export class AuthService extends Context.Tag("AuthService")<
  AuthService,
  {
    /**
     * Get current authenticated user
     * Returns NotFoundError if not authenticated (does not redirect)
     */
    readonly getCurrentUser: () => Effect.Effect<
      UserIdentity,
      AuthError | NotFoundError,
      never
    >;

    /**
     * Get current session with full user data
     * Returns NotFoundError if not authenticated (does not redirect)
     */
    readonly getSession: () => Effect.Effect<
      SessionData,
      AuthError | NotFoundError,
      never
    >;

    /**
     * Verify user ID matches authenticated user
     * Security check to prevent unauthorized access
     */
    readonly verifyUserId: (
      userId: string
    ) => Effect.Effect<UserIdentity, AuthError | NotFoundError, never>;

    /**
     * Check if user has specific authentication method
     */
    readonly hasAuthMethod: (
      provider: string
    ) => Effect.Effect<boolean, AuthError | NotFoundError, never>;
  }
>() {}

/**
 * Transform Supabase User to UserIdentity
 */
const transformUser = (user: User): UserIdentity => {
  const identityProviders = new Set(
    user.identities?.map((identity) => identity.provider) ?? []
  );

  return {
    id: user.id,
    email: user.email ?? null,
    phone: user.phone ?? null,
    firstName: (user.user_metadata?.first_name as string | null) ?? null,
    metadata: user.user_metadata ?? {},
    identityProviders,
  };
};

/**
 * Live implementation of AuthService
 *
 * Uses Effect Cache for session caching to avoid repeated auth checks
 */
export const AuthServiceLive = Layer.effect(
  AuthService,
  Effect.gen(function* () {
    const supabase = yield* SupabaseService;

    // Create cache for session data (5 minute TTL)
    const sessionCache = yield* Cache.make({
      capacity: 100,
      timeToLive: Duration.minutes(5),
      lookup: (key: "current-session") =>
        Effect.gen(function* () {
          const client = yield* supabase.getClient();

          const authResult = yield* Effect.tryPromise({
            try: () => client.auth.getUser(),
            catch: (error) =>
              new AuthError({
                reason: "invalid_session",
                cause: error,
              }),
          });

          // Cast to known type from Supabase
          const result = authResult as { data: { user: User | null }, error: any };

          if (result.error) {
            return yield* Effect.fail(
              new AuthError({
                reason: "invalid_session",
                cause: result.error,
              })
            );
          }

          if (!result.data.user) {
            return yield* Effect.fail(
              new NotFoundError({
                resource: "User session",
              })
            );
          }

          const userIdentity = transformUser(result.data.user);

          return {
            user: userIdentity,
            rawUser: result.data.user,
          };
        }),
    });

    return {
      /**
       * Get current user with caching
       */
      getCurrentUser: () =>
        Effect.gen(function* () {
          const session = yield* sessionCache.get("current-session");
          return session.user;
        }),

      /**
       * Get full session data
       */
      getSession: () => sessionCache.get("current-session"),

      /**
       * Verify user ID matches authenticated user
       */
      verifyUserId: (userId: string) =>
        Effect.gen(function* () {
          const session = yield* sessionCache.get("current-session");

          if (session.user.id !== userId) {
            return yield* Effect.fail(
              new AuthError({
                reason: "unauthorized",
                cause: new Error(
                  `User ID mismatch: expected ${session.user.id}, got ${userId}`
                ),
              })
            );
          }

          return session.user;
        }),

      /**
       * Check if user has specific auth method
       */
      hasAuthMethod: (provider: string) =>
        Effect.gen(function* () {
          const session = yield* sessionCache.get("current-session");
          return session.user.identityProviders.has(provider);
        }),
    };
  })
);

/**
 * Convenience function to provide AuthServiceLive with dependencies
 */
export const withAuth = <A, E, R>(
  effect: Effect.Effect<A, E, R | AuthService>
): Effect.Effect<A, E, Exclude<R, AuthService> | SupabaseService> =>
  Effect.provide(effect, AuthServiceLive);
