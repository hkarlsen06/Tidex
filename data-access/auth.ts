/**
 * Authentication Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * This module provides session verification and user authentication.
 *
 * Migration status: Using Effect-based AuthService internally
 */

import 'server-only'
import { cache } from 'react'
import { redirect } from 'next/navigation'
import { cookies } from 'next/headers'
import { Effect } from 'effect'
import { AuthService } from '@/lib/services/auth'
import { SupabaseAuthLive } from '@/lib/layers/app'

/**
 * Verify user session and redirect to login if not authenticated
 * Use this in Server Components and Server Actions
 *
 * Promise wrapper around Effect-based authentication
 */
export const verifySession = cache(async () => {
  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  // This must happen before Effect Cache uses Date.now()
  await cookies();

  const program = Effect.gen(function* () {
    const auth = yield* AuthService;
    const session = yield* auth.getSession();
    return session;
  }).pipe(
    Effect.provide(SupabaseAuthLive),
    Effect.scoped
  );

  try {
    const result = await Effect.runPromise(program);
    // Return format compatible with existing code
    return { user: result.rawUser };
  } catch {
    // Handle authentication errors by redirecting
    // redirect() throws a NEXT_REDIRECT error that Next.js catches
    redirect('/login');
  }
});

/**
 * Get user session without redirecting
 * Returns null if not authenticated
 * Use this in API routes where redirect() is not supported
 *
 * Promise wrapper around Effect-based authentication
 */
export const getSession = cache(async () => {
  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  // This must happen before Effect Cache uses Date.now()
  await cookies();

  const program = Effect.gen(function* () {
    const auth = yield* AuthService;
    const session = yield* auth.getSession();
    return session;
  }).pipe(
    Effect.provide(SupabaseAuthLive),
    Effect.scoped
  );

  try {
    const result = await Effect.runPromise(program);
    // Return format compatible with existing code
    return { user: result.rawUser };
  } catch {
    // Authentication failed - return null without redirecting
    // This is expected behavior (e.g., on login page before authentication)
    return null;
  }
});
