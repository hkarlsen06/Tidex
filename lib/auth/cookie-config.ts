/**
 * Shared cookie configuration utilities for locale and other non-Supabase cookies
 *
 * IMPORTANT: Supabase auth cookie configuration has been removed.
 * As of the latest @supabase/ssr best practices (2025), cookie options should
 * be managed by Supabase itself via the options parameter passed to setAll().
 *
 * DO NOT override Supabase's cookie options in the setAll callback:
 * ✅ Correct: response.cookies.set(name, value, options)
 * ❌ Wrong:   response.cookies.set(name, value, { ...CUSTOM_OPTIONS, ...options })
 *
 * This file now only contains utilities for non-Supabase cookies (like locale).
 */

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
 * DEPRECATED: All Supabase cookie configuration functions have been removed
 *
 * As of @supabase/ssr latest best practices (2025), Supabase manages its own
 * cookie options internally. You should pass the options parameter from
 * Supabase's setAll callback directly to your cookie-setting method without
 * modification.
 *
 * These functions are deprecated and should not be used:
 * - buildServerCookieOptions() - REMOVED
 * - buildProxyCookieOptions() - REMOVED
 * - buildBrowserCookieOptions() - REMOVED
 *
 * For non-Supabase cookies (like locale), use resolveSecureFlag() to determine
 * the appropriate secure flag value.
 */
