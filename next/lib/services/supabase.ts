/**
 * Supabase Service Layer
 *
 * Effect-based service for Supabase database operations with:
 * - Scoped resource management (automatic cleanup)
 * - Retry logic with exponential backoff
 * - Timeout handling
 * - Typed error handling
 * - Request deduplication
 *
 * Usage:
 * ```typescript
 * const program = Effect.gen(function* () {
 *   const supabase = yield* SupabaseService
 *   const result = yield* supabase.query((client) =>
 *     client.from('shifts').select('*').eq('user_id', userId)
 *   )
 *   return result
 * }).pipe(
 *   Effect.provide(SupabaseServiceLive)
 * )
 * ```
 */

import "server-only";
import { Context, Effect, Layer, Schedule, Duration, Redacted, Scope } from "effect";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import { cookies, headers } from "next/headers";
import { SupabaseError, TimeoutError, DatabaseError } from "../errors/tagged";
import { AppConfig } from "./config";

/**
 * Type for Supabase query result
 */
export type SupabaseQueryResult<T> = {
  data: T | null;
  error: {
    message: string;
    code?: string;
    details?: string;
    hint?: string;
  } | null;
};

/**
 * Helper to check if error is read-only cookies error
 */
const isReadonlyCookiesError = (err: unknown): boolean =>
  err instanceof Error &&
  err.message.includes("Cookies can only be modified in a Server Action or Route Handler");

/**
 * Supabase Service Interface
 */
export class SupabaseService extends Context.Tag("SupabaseService")<
  SupabaseService,
  {
    /**
     * Execute a query with retry logic and timeout
     * @param callback - Function that executes Supabase query
     * @param options - Query options (timeout, retries)
     */
    readonly query: <T>(
      callback: (client: SupabaseClient) => Promise<SupabaseQueryResult<T>>,
      options?: {
        timeout?: Duration.DurationInput;
        retries?: number;
      }
    ) => Effect.Effect<T, SupabaseError | TimeoutError | DatabaseError, never>;

    /**
     * Get the raw Supabase client
     * Use sparingly - prefer `query` method for automatic error handling
     */
    readonly getClient: () => Effect.Effect<SupabaseClient, never, never>;
  }
>() {}

/**
 * Default retry schedule: 3 attempts with exponential backoff (100ms, 200ms, 400ms)
 */
const defaultRetrySchedule = Schedule.exponential(Duration.millis(100)).pipe(
  Schedule.compose(Schedule.recurs(2)) // Total 3 attempts (initial + 2 retries)
);

/**
 * Live implementation of SupabaseService
 *
 * IMPORTANT: Creates a fresh client for each operation to ensure Bearer token
 * from iOS requests is properly detected. The client is NOT cached because
 * the Authorization header needs to be read fresh for each request context.
 */
export const SupabaseServiceLive = Layer.effect(
  SupabaseService,
  Effect.gen(function* () {
    // Get config once (this is safe to cache)
    const config = yield* AppConfig;

    /**
     * Create a fresh Supabase client with current request context
     * This is called for each query/getClient to ensure Bearer tokens are detected
     */
    const createFreshClient = Effect.gen(function* () {
      // Check for Bearer token in Authorization header (native iOS app)
      const headerStore = yield* Effect.promise(() => headers());
      const authHeader = headerStore.get("Authorization");

      if (authHeader?.startsWith("Bearer ")) {
        const token = authHeader.substring(7);

        // Use direct Supabase URL for Bearer token auth (bypasses auth proxy)
        // The auth proxy (e.g., identity.tidex.no) only handles authentication,
        // not database REST API calls
        const directUrl = process.env.SUPABASE_DIRECT_URL || config.supabase.url;

        // Create client with Bearer token authentication
        const client = createClient(
          directUrl,
          Redacted.value(config.supabase.publishableKey),
          {
            global: {
              headers: {
                Authorization: `Bearer ${token}`,
              },
            },
          }
        );

        // Suppress getSession warning - we use getClaims() for auth validation
        // @ts-expect-error: suppressGetSessionWarning is not in types but works
        client.auth.suppressGetSessionWarning = true;

        return client;
      }

      // Fall back to cookie-based authentication (web app)
      const store = yield* Effect.promise(() => cookies());

      const client = createServerClient(
        config.supabase.url,
        Redacted.value(config.supabase.publishableKey),
        {
          cookies: {
            getAll() {
              return store.getAll().map(({ name, value }) => ({ name, value }));
            },
            setAll(cookiesToSet) {
              for (const { name, value, options } of cookiesToSet) {
                try {
                  store.set(name, value, options);
                } catch (err) {
                  if (!isReadonlyCookiesError(err)) {
                    console.warn("[Supabase Service] Failed to set cookie:", name, err);
                  }
                }
              }
            },
          },
        }
      );

      // Suppress getSession warning - we use getClaims() for auth validation
      // @ts-expect-error: suppressGetSessionWarning is not in types but works
      client.auth.suppressGetSessionWarning = true;

      return client;
    });

    return {
      /**
       * Execute a query with automatic retry, timeout, and error handling
       * Creates a fresh client for each query to respect request context
       */
      query: <T>(
        callback: (client: SupabaseClient) => Promise<SupabaseQueryResult<T>>,
        options?: {
          timeout?: Duration.DurationInput;
          retries?: number;
        }
      ): Effect.Effect<T, SupabaseError | TimeoutError | DatabaseError, never> => {
        const queryEffect = Effect.gen(function* () {
          const client = yield* createFreshClient;
          return yield* Effect.tryPromise({
            try: () => callback(client),
            catch: (error) =>
              new SupabaseError({
                operation: "query",
                cause: error,
              }),
          });
        }).pipe(
          // Check for Supabase-level errors
          // Note: null data without error is valid (e.g., .maybeSingle() with no rows)
          Effect.flatMap((result) => {
            if (result.error) {
              return Effect.fail(
                new DatabaseError({
                  query: "supabase query",
                  code: result.error.code ?? "UNKNOWN",
                  errorMessage: result.error.message,
                  cause: result.error,
                })
              );
            }
            // Return data as-is (may be null for .maybeSingle() with no rows)
            return Effect.succeed(result.data as T);
          }),
          // Add retry logic (only for network/timeout errors, not for validation errors)
          Effect.retry(
            options?.retries !== undefined
              ? Schedule.recurs(options.retries)
              : defaultRetrySchedule
          )
        );

        return queryEffect;
      },

      /**
       * Get raw client (creates fresh client to respect request context)
       */
      getClient: () => createFreshClient,
    };
  })
);

/**
 * Convenience function to provide SupabaseServiceLive
 * Use this when you need Supabase + Config together
 * Note: Still requires Scope - use Effect.scoped if needed
 */
export const withSupabase = <A, E, R>(
  effect: Effect.Effect<A, E, R | SupabaseService>
): Effect.Effect<A, E, Exclude<R, SupabaseService> | AppConfig | Scope.Scope> =>
  Effect.provide(effect, SupabaseServiceLive);
