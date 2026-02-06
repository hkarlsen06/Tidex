/**
 * Authentication Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * This module provides session verification and user authentication.
 *
 * Supports both cookie-based auth (web) and Bearer token auth (iOS native app).
 * Bearer token support allows iOS to call DAL functions through API routes
 * without needing separate authentication handling.
 *
 * Migration status: Using Effect-based AuthService internally
 */

import 'server-only'
import { cache } from 'react'
import { redirect } from 'next/navigation'
import { cookies, headers } from 'next/headers'
import { Effect } from 'effect'
import { createClient } from '@supabase/supabase-js'
import { AuthService } from '@/lib/services/auth'
import { SupabaseAuthLive } from '@/lib/layers/app'
import { LOCALE_COOKIE, defaultLocale, locales, type Locale } from '@/lib/i18n/config'
import { ENV } from '@/lib/env'

/**
 * Try to authenticate using Bearer token from Authorization header.
 * Used by iOS native app which sends JWT tokens instead of cookies.
 *
 * @returns User object if Bearer token is valid, null otherwise
 */
async function tryBearerAuth() {
  try {
    const headerStore = await headers();
    const authHeader = headerStore.get("Authorization");

    if (!authHeader?.startsWith("Bearer ")) {
      return null;
    }

    const jwt = authHeader.slice(7);
    const supabase = createClient(ENV.URL!, ENV.PUBLISHABLE!);
    const { data: { user }, error } = await supabase.auth.getUser(jwt);

    if (error || !user) {
      return null;
    }

    return user;
  } catch {
    return null;
  }
}

/**
 * Verify user session and redirect to login if not authenticated
 * Use this in Server Components and Server Actions
 *
 * Supports both:
 * - Cookie-based auth (web browsers)
 * - Bearer token auth (iOS native app via Authorization header)
 *
 * Promise wrapper around Effect-based authentication
 */
export const verifySession = cache(async () => {
  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  // This must happen before Effect Cache uses Date.now()
  const cookieStore = await cookies();

  // Try Bearer token auth first (iOS native app)
  const bearerUser = await tryBearerAuth();
  if (bearerUser) {
    return { user: bearerUser };
  }

  // Fall back to cookie-based auth (web)
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
    // Get locale from cookie for redirect, avoiding extra redirect hop through proxy
    const localeCookie = cookieStore.get(LOCALE_COOKIE)?.value;
    const locale: Locale = localeCookie && locales.includes(localeCookie as Locale)
      ? (localeCookie as Locale)
      : defaultLocale;

    // Handle authentication errors by redirecting
    // redirect() throws a NEXT_REDIRECT error that Next.js catches
    redirect(`/${locale}/login`);
  }
});

/**
 * Get user session without redirecting
 * Returns null if not authenticated
 * Use this in API routes where redirect() is not supported
 *
 * Supports both:
 * - Cookie-based auth (web browsers)
 * - Bearer token auth (iOS native app via Authorization header)
 *
 * Promise wrapper around Effect-based authentication
 */
export const getSession = cache(async () => {
  // Call cookies() early to satisfy Next.js 16 prerendering requirements
  // This must happen before Effect Cache uses Date.now()
  try {
    await cookies();
  } catch {
    // During prerender without a live request context, cookies() can reject.
    // Treat this as unauthenticated for API consumers.
    return null;
  }

  // Try Bearer token auth first (iOS native app)
  const bearerUser = await tryBearerAuth();
  if (bearerUser) {
    return { user: bearerUser };
  }

  // Fall back to cookie-based auth (web)
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

/**
 * Verify admin status and redirect to settings if not admin
 * Use this in Server Components and Server Actions for admin-only pages
 *
 * Server-side is the source of truth - client-side isAdmin checks are cosmetic only
 */
export const verifyAdmin = cache(async () => {
  const session = await verifySession();
  const isAdmin = (session.user.app_metadata?.role as string) === 'admin';
  if (!isAdmin) {
    // Get locale from cookie for redirect, avoiding extra redirect hop through proxy
    const cookieStore = await cookies();
    const localeCookie = cookieStore.get(LOCALE_COOKIE)?.value;
    const locale: Locale = localeCookie && locales.includes(localeCookie as Locale)
      ? (localeCookie as Locale)
      : defaultLocale;

    redirect(`/${locale}/settings`);
  }
  return session;
});
