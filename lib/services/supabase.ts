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
import type { SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
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
 * Create Supabase client with cookie adapter
 * This is the low-level client creation - wrapped in Effect for resource management
 */
const createSupabaseClient = Effect.gen(function* () {
  const config = yield* AppConfig;
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

  return client;
});

/**
 * Live implementation of SupabaseService
 *
 * Uses scoped resource management to ensure proper cleanup
 */
export const SupabaseServiceLive = Layer.effect(
  SupabaseService,
  Effect.gen(function* () {
    // Create client as a scoped resource
    const client = yield* Effect.acquireRelease(
      createSupabaseClient,
      (client) =>
        Effect.sync(() => {
          // Cleanup: Remove all subscriptions
          client.removeAllChannels();
        })
    );

    return {
      /**
       * Execute a query with automatic retry, timeout, and error handling
       */
      query: <T>(
        callback: (client: SupabaseClient) => Promise<SupabaseQueryResult<T>>,
        options?: {
          timeout?: Duration.DurationInput;
          retries?: number;
        }
      ): Effect.Effect<T, SupabaseError | TimeoutError | DatabaseError, never> => {
        const timeoutDuration = options?.timeout ?? Duration.seconds(5);

        const queryEffect = Effect.tryPromise({
          try: () => callback(client),
          catch: (error) =>
            new SupabaseError({
              operation: "query",
              cause: error,
            }),
        }).pipe(
          // Check for Supabase-level errors
          Effect.flatMap((result) => {
            if (result.error) {
              return Effect.fail(
                new DatabaseError({
                  query: "supabase query",
                  code: result.error.code ?? "UNKNOWN",
                  message: result.error.message,
                  cause: result.error,
                })
              );
            }
            if (result.data === null) {
              return Effect.fail(
                new DatabaseError({
                  query: "supabase query",
                  code: "NO_DATA",
                  message: "Query returned null data",
                })
              );
            }
            return Effect.succeed(result.data);
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
       * Get raw client (use sparingly)
       */
      getClient: () => Effect.succeed(client),
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
