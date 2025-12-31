import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { locales, defaultLocale, LOCALE_COOKIE, type Locale } from "@/lib/i18n/config";
import { resolveSecureFlag } from "@/lib/auth/cookie-config";

/**
 * Next.js 16 Proxy for Supabase Token Refresh and Locale Routing
 *
 * Purpose:
 * 1. Refresh expired auth tokens and sync cookies between client/server
 * 2. Handle locale-based routing with URL prefixes (/en/*, /no/*)
 * 3. Redirect paths without locale to user's preferred locale
 *
 * Does NOT perform authentication - that's handled in Server Components (layouts/pages).
 *
 * This follows Next.js 16 best practices:
 * - Proxy handles token refresh and locale routing (cookie management)
 * - Authentication logic lives in the data access layer (Server Components)
 * - Uses getClaims() for token refresh (triggers refresh when token is about to expire)
 * - IMPORTANT: Uses Supabase's cookie options directly without overriding
 *
 * Token Refresh Strategy:
 * - getClaims() refreshes the session first if the access token is about to expire,
 *   then validates the JWT (often without network call using asymmetric keys + JWKS cache)
 * - getUser() is heavier as it always makes a network request to fetch user details
 * - Use getUser() only when you need server-verified session state (e.g., checking if
 *   user has been logged out/revoked server-side)
 *
 * See: https://supabase.com/docs/reference/javascript/auth-getclaims
 */

/**
 * Extract locale from pathname
 * Returns locale if found in URL, null otherwise
 */
function getLocaleFromPathname(pathname: string): Locale | null {
  const segments = pathname.split('/');
  const potentialLocale = segments[1];

  if (potentialLocale && locales.includes(potentialLocale as Locale)) {
    return potentialLocale as Locale;
  }

  return null;
}

/**
 * Detect locale from Accept-Language header
 * Returns the best matching supported locale or default
 */
function detectLocaleFromHeader(request: NextRequest): Locale {
  const acceptLanguage = request.headers.get('accept-language');
  if (!acceptLanguage) return defaultLocale;

  // Parse Accept-Language header (e.g., "en-US,en;q=0.9,no;q=0.8")
  const languages = acceptLanguage
    .split(',')
    .map(lang => {
      const [code, qValue] = lang.trim().split(';');
      const quality = qValue ? parseFloat(qValue.split('=')[1]) : 1.0;
      return { code: code.split('-')[0].toLowerCase(), quality };
    })
    .sort((a, b) => b.quality - a.quality);

  // Find first matching supported locale
  for (const { code } of languages) {
    if (locales.includes(code as Locale)) {
      return code as Locale;
    }
  }

  return defaultLocale;
}

/**
 * Check if path should skip locale routing
 */
function shouldSkipLocaleRouting(pathname: string): boolean {
  return (
    pathname.startsWith('/api/') ||
    pathname.startsWith('/_next/') ||
    pathname.startsWith('/auth/callback') ||
    pathname.startsWith('/monitoring') ||
    pathname.startsWith('/.well-known/') ||
    pathname === '/favicon.ico' ||
    pathname === '/manifest.json' ||
    pathname === '/support' ||
    /\.(svg|png|jpg|jpeg|gif|webp|ico)$/.test(pathname)
  );
}

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Early exit for static assets (before Supabase initialization)
  if (
    pathname.startsWith('/_next/static') ||
    pathname.startsWith('/_next/image') ||
    /\.(css|js|map)$/.test(pathname)
  ) {
    return NextResponse.next();
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  // If Supabase isn't configured, let the request through
  // Server Components will handle auth validation
  if (!supabaseUrl || !supabaseKey) {
    return NextResponse.next();
  }

  // Skip locale routing for API routes, static files, etc.
  if (shouldSkipLocaleRouting(pathname)) {
    const response = NextResponse.next({
      request: {
        headers: request.headers,
      },
    });

    // Trigger Supabase token refresh for API routes
    // getClaims() refreshes the session first if the access token is about to expire,
    // then validates the JWT. With asymmetric keys + warm JWKS cache, this is often
    // faster than getUser() which always makes a network request.
    const supabase = createServerClient(supabaseUrl, supabaseKey, {
      cookies: {
        getAll() {
          return request.cookies.getAll().map(({ name, value }) => ({ name, value }));
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            response.cookies.set(name, value, options);
          });
        },
      },
    });

    // getClaims() triggers token refresh if needed and updates cookies via setAll
    await supabase.auth.getClaims();

    return response;
  }

  // Check if pathname already has a locale
  const localeFromPath = getLocaleFromPathname(pathname);

  if (localeFromPath) {
    // Path has locale - update cookie and continue
    // Add x-current-path header so server components can access the current path
    const requestHeaders = new Headers(request.headers);
    requestHeaders.set('x-current-path', pathname);

    const response = NextResponse.next({
      request: {
        headers: requestHeaders,
      },
    });

    // Update locale cookie if it differs
    const existingLocale = request.cookies.get(LOCALE_COOKIE)?.value;
    if (existingLocale !== localeFromPath) {
      response.cookies.set(LOCALE_COOKIE, localeFromPath, {
        path: '/',
        sameSite: 'lax',
        maxAge: 60 * 60 * 24 * 365, // 1 year
        secure: resolveSecureFlag(request.nextUrl.protocol, request.nextUrl.hostname),
      });
    }

    // Trigger Supabase token refresh
    // getClaims() refreshes the session first if the access token is about to expire,
    // then validates the JWT. With asymmetric keys + warm JWKS cache, this is often
    // faster than getUser() which always makes a network request.
    const supabase = createServerClient(supabaseUrl, supabaseKey, {
      cookies: {
        getAll() {
          return request.cookies.getAll().map(({ name, value }) => ({ name, value }));
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            response.cookies.set(name, value, options);
          });
        },
      },
    });

    // getClaims() triggers token refresh if needed and updates cookies via setAll
    await supabase.auth.getClaims();

    return response;
  }

  // No locale in path - determine locale and redirect
  const cookieLocale = request.cookies.get(LOCALE_COOKIE)?.value;
  let targetLocale: Locale;

  if (cookieLocale && locales.includes(cookieLocale as Locale)) {
    // Use saved locale from cookie
    targetLocale = cookieLocale as Locale;
  } else {
    // Detect from Accept-Language header
    targetLocale = detectLocaleFromHeader(request);
  }

  // Redirect to locale-prefixed path
  const redirectUrl = new URL(`/${targetLocale}${pathname}`, request.url);
  const response = NextResponse.redirect(redirectUrl);

  // Set locale cookie
  response.cookies.set(LOCALE_COOKIE, targetLocale, {
    path: '/',
    sameSite: 'lax',
    maxAge: 60 * 60 * 24 * 365, // 1 year
    secure: resolveSecureFlag(request.nextUrl.protocol, request.nextUrl.hostname),
  });

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
