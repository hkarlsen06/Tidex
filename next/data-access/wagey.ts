/**
 * Wagey Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * Provides access control and usage tracking for Wagey AI assistant.
 *
 * Usage:
 * ```typescript
 * // In server component or server action
 * const access = await getWageyAccess();
 * if (!access.hasAccess) {
 *   // Show upgrade prompt
 * }
 *
 * // Before processing a chat message
 * const result = await useWageyInvocation(userId);
 * if (!result.allowed) {
 *   // Show limit reached message
 * }
 * ```
 */

import "server-only";
import { cache } from "react";
import { cacheTag } from "next/cache";
import { cookies } from "next/headers";
import { Effect } from "effect";
import { WageyService } from "@/lib/services/wagey";
import { WageyLive } from "@/lib/layers/app";
import { logger } from "@/lib/logger";
import { verifySession } from "@/data-access/auth";
import type {
  WageyAccessResult,
  WageyInvocationResult,
  WageyTurnResult,
} from "@/lib/wagey/types";

// Re-export types for convenience
export type { WageyAccessResult, WageyInvocationResult, WageyTurnResult };

const FALLBACK_WAGEY_ACCESS: WageyAccessResult = {
  level: "free",
  hasAccess: false,
  limit: 0,
  used: 0,
  remaining: 0,
  bonus: 0,
  resetDate: null,
};

const FALLBACK_WAGEY_INVOCATION: WageyInvocationResult = {
  allowed: false,
  count: 0,
  remaining: 0,
  bonus: 0,
};

/**
 * Internal implementation of getWageyAccess using Effect
 * @internal - Do not call directly, use getWageyAccess()
 */
async function getWageyAccessInternal(userId: string): Promise<WageyAccessResult> {
  "use cache: private";
  cacheTag(`user-${userId}`, "wagey-access");

  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  await cookies();

  const program = Effect.gen(function* () {
    const wagey = yield* WageyService;
    const access = yield* wagey.getWageyAccess(userId);
    return access;
  }).pipe(Effect.provide(WageyLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return result;
  } catch (error: any) {
    logger.error("Failed to get Wagey access:", error);
    // Return no access on error (safe default)
    return {
      level: "free",
      hasAccess: false,
      limit: 0,
      used: 0,
      remaining: 0,
      bonus: 0,
      resetDate: null,
    };
  }
}

/**
 * Get Wagey access status for the authenticated user
 *
 * - Uses React cache() for request deduplication
 * - Automatically verifies user session
 * - Returns access level, limits, and usage counts
 *
 * @returns WageyAccessResult with access status and usage info
 */
export const getWageyAccess = cache(async (): Promise<WageyAccessResult> => {
  const { user } = await verifySession();
  return getWageyAccessInternal(user.id);
});

/**
 * Attempt to use a Wagey invocation (for API route use)
 *
 * This function:
 * 1. Checks the user's tier and limit
 * 2. Atomically increments the counter if allowed
 * 3. Returns whether the message can be processed
 *
 * Note: This is NOT cached as it performs a write operation.
 * Should be called from the chat router before processing messages.
 *
 * @param userId - The authenticated user's ID
 * @returns WageyInvocationResult with allowed status and remaining count
 */
export async function useWageyInvocation(
  userId: string
): Promise<WageyInvocationResult> {
  const program = Effect.gen(function* () {
    const wagey = yield* WageyService;
    const result = yield* wagey.useInvocation(userId);
    return result;
  }).pipe(Effect.provide(WageyLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return result;
  } catch (error: any) {
    logger.error("Failed to use Wagey invocation:", error);
    // Return not allowed on error (safe default)
    return {
      allowed: false,
      count: 0,
      remaining: 0,
      bonus: 0,
    };
  }
}

/**
 * Initialize a Wagey chat turn in one request-scoped operation.
 *
 * This verifies auth, resolves tier/usage metadata, and performs the atomic
 * invocation increment without duplicating the same service work across calls.
 */
export async function beginWageyTurn(userId: string): Promise<WageyTurnResult> {
  const program = Effect.gen(function* () {
    const wagey = yield* WageyService;
    const result = yield* wagey.beginTurn(userId);
    return result;
  }).pipe(
    Effect.catchTags({
      DatabaseError: (error) => {
        logger.error("Failed to initialize Wagey turn:", error);
        return Effect.succeed({
          access: FALLBACK_WAGEY_ACCESS,
          invocation: FALLBACK_WAGEY_INVOCATION,
        });
      },
      SupabaseError: (error) => {
        logger.error("Failed to initialize Wagey turn:", error);
        return Effect.succeed({
          access: FALLBACK_WAGEY_ACCESS,
          invocation: FALLBACK_WAGEY_INVOCATION,
        });
      },
      TimeoutError: (error) => {
        logger.error("Failed to initialize Wagey turn:", error);
        return Effect.succeed({
          access: FALLBACK_WAGEY_ACCESS,
          invocation: FALLBACK_WAGEY_INVOCATION,
        });
      },
    }),
    Effect.provide(WageyLive),
    Effect.scoped
  );

  try {
    return await Effect.runPromise(program);
  } catch (error: any) {
    logger.error("Failed to initialize Wagey turn:", error);
    throw error;
  }
}

/**
 * Check if user has Wagey access without using an invocation
 *
 * Use this for quick access checks without incrementing usage.
 * For chat message processing, use useWageyInvocation() instead.
 *
 * @param userId - The authenticated user's ID
 * @returns boolean - whether user can access Wagey
 */
export async function hasWageyAccess(userId: string): Promise<boolean> {
  const access = await getWageyAccessInternal(userId);
  return access.hasAccess;
}

/**
 * Get Wagey access for a specific user ID (Route Handler compatible)
 *
 * Use this in Route Handlers where verifySession()/redirect() doesn't work.
 * The caller is responsible for authentication verification.
 *
 * @param userId - The authenticated user's ID (caller must verify auth)
 * @returns WageyAccessResult with access status and usage info
 */
export async function getWageyAccessForUser(
  userId: string
): Promise<WageyAccessResult> {
  return getWageyAccessInternal(userId);
}
