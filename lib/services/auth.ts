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
import { Context, Effect, Layer } from "effect";
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
 * Live implementation of AuthService
 *
 * SECURITY: Does NOT use persistent caching to prevent session data leaking
 * between users. Request-level deduplication is handled by React's cache()
 * in data-access/auth.ts.
 *
 * Uses getClaims() for performance - parses JWT locally instead of network request.
 * See: https://supabase.com/docs/reference/javascript/auth-getclaims
 */
export const AuthServiceLive = Layer.effect(
  AuthService,
  Effect.gen(function* () {
    const supabase = yield* SupabaseService;

    /**
     * Fetch session data from JWT claims
     * This is called fresh for each request to prevent cross-user session leaks.
     * getClaims() is fast (local JWT parsing, no network request).
     */
    const fetchSession = (): Effect.Effect<
      SessionData,
      AuthError | NotFoundError,
      never
    > =>
      Effect.gen(function* () {
        const client = yield* supabase.getClient();

        // Use getClaims() for performance - parses JWT locally without network request
        // This is faster than getUser() which always makes a server request
        const claimsResult = yield* Effect.tryPromise({
          try: () => client.auth.getClaims(),
          catch: (error) =>
            new AuthError({
              reason: "invalid_session",
              cause: error,
            }),
        });

        // Cast to known type from Supabase
        const result = claimsResult as {
          data: {
            claims: {
              sub: string;
              email?: string;
              phone?: string;
              user_metadata?: Record<string, unknown>;
              app_metadata?: {
                provider?: string;
                providers?: string[];
              };
            } | null;
          } | null;
          error: any;
        };

        if (result.error) {
          return yield* Effect.fail(
            new AuthError({
              reason: "invalid_session",
              cause: result.error,
            })
          );
        }

        if (!result.data?.claims) {
          return yield* Effect.fail(
            new NotFoundError({
              resource: "User session",
            })
          );
        }

        const claims = result.data.claims;

        // Extract identity providers from app_metadata
        const providers = claims.app_metadata?.providers ?? [];
        const identityProviders = new Set(providers);

        const userIdentity: UserIdentity = {
          id: claims.sub,
          email: claims.email ?? null,
          phone: claims.phone ?? null,
          firstName: (claims.user_metadata?.full_name as string | null) ?? null,
          metadata: claims.user_metadata ?? {},
          identityProviders,
        };

        // Create a minimal User object for backward compatibility
        // Note: This doesn't have full User data, but has what's needed for most operations
        const rawUser: User = {
          id: claims.sub,
          email: claims.email,
          phone: claims.phone,
          user_metadata: claims.user_metadata ?? {},
          app_metadata: claims.app_metadata ?? {},
          aud: "authenticated",
          created_at: "",
        } as User;

        return {
          user: userIdentity,
          rawUser,
        };
      });

    return {
      /**
       * Get current user (fresh fetch, no persistent cache)
       */
      getCurrentUser: () =>
        Effect.gen(function* () {
          const session = yield* fetchSession();
          return session.user;
        }),

      /**
       * Get full session data (fresh fetch, no persistent cache)
       */
      getSession: () => fetchSession(),

      /**
       * Verify user ID matches authenticated user
       */
      verifyUserId: (userId: string) =>
        Effect.gen(function* () {
          const session = yield* fetchSession();

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
          const session = yield* fetchSession();
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
