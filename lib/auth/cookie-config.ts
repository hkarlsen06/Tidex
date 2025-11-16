/**
 * Shared cookie configuration for Supabase auth
 *
 * CRITICAL: Server-side Supabase clients (proxy, server) must use identical
 * cookie settings to prevent "Refresh Token Not Found" errors caused by
 * cookie read/write mismatches.
 *
 * IMPORTANT: Browser clients should NOT use cookieOptions - @supabase/ssr
 * handles browser cookies automatically via document.cookie API.
 */

import type { CookieOptions } from "@supabase/ssr";

const ONE_WEEK_SECONDS = 60 * 60 * 24 * 7;

/**
 * Determine if cookies should have the secure flag based on environment
 */
function envPrefersSecureCookies(): boolean {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (siteUrl) {
    return siteUrl.startsWith("https");
  }
  return process.env.NODE_ENV === "production";
}

/**
 * Check if hostname is a loopback address (localhost, 127.0.0.1, ::1)
 */
function isLoopbackHost(hostname: string): boolean {
  const lower = hostname.toLowerCase();
  return (
    lower === "localhost" ||
    lower.startsWith("localhost:") ||
    lower === "127.0.0.1" ||
    lower.startsWith("127.0.0.1:") ||
    lower === "[::1]" ||
    lower.startsWith("[::1]:")
  );
}

/**
 * Resolve secure flag based on protocol and hostname
 *
 * @param protocol - URL protocol (e.g., "https:", "http:")
 * @param hostname - URL hostname (e.g., "localhost", "example.com")
 */
export function resolveSecureFlag(
  protocol: string | undefined,
  hostname: string | undefined
): boolean {
  // HTTPS always requires secure cookies
  if (protocol === "https:") return true;

  // HTTP on loopback is allowed without secure
  if (protocol === "http:") {
    if (hostname && isLoopbackHost(hostname)) {
      return false;
    }
    // HTTP on non-loopback should still use secure=false
    // (some dev environments use local IPs)
    return false;
  }

  // Fallback to environment preference
  if (hostname && isLoopbackHost(hostname)) return false;
  return envPrefersSecureCookies();
}

/**
 * Build base cookie options for server-side use (RSC, Server Actions)
 * Uses environment-based secure flag
 */
export function buildServerCookieOptions(): Partial<CookieOptions> {
  return {
    httpOnly: true,
    secure: envPrefersSecureCookies(),
    sameSite: "lax",
    path: "/",
    maxAge: ONE_WEEK_SECONDS,
  };
}

/**
 * Build base cookie options for proxy/middleware use
 * Uses request-based secure flag
 *
 * @param protocol - Request protocol from NextRequest.nextUrl.protocol
 * @param hostname - Request hostname from NextRequest.nextUrl.hostname
 */
export function buildProxyCookieOptions(
  protocol: string,
  hostname: string
): Partial<CookieOptions> {
  return {
    httpOnly: true,
    secure: resolveSecureFlag(protocol, hostname),
    sameSite: "lax",
    path: "/",
    maxAge: ONE_WEEK_SECONDS,
  };
}

/**
 * DEPRECATED: Browser clients should NOT use cookieOptions parameter
 *
 * The @supabase/ssr library's createBrowserClient handles cookies automatically
 * using the document.cookie API. Passing cookieOptions to browser clients causes
 * cookie mismatch issues with server-side clients.
 *
 * This function is kept for reference but should not be used.
 */
export function buildBrowserCookieOptions(): Partial<CookieOptions> {
  throw new Error(
    "buildBrowserCookieOptions is deprecated. Browser clients should not use cookieOptions parameter."
  );
}
