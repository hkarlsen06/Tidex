import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createServerClient, type CookieOptions } from "@supabase/ssr";

/**
 * Next.js 16 Proxy for Supabase Token Refresh
 *
 * Purpose: Refresh expired auth tokens and sync cookies between client/server.
 * Does NOT perform authentication - that's handled in Server Components (layouts/pages).
 *
 * This follows Next.js 16 best practices:
 * - Proxy handles token refresh (cookie management)
 * - Authentication logic lives in the data access layer (Server Components)
 * - No network I/O beyond what Supabase SSR needs for token refresh
 */

function isLoopbackHost(hostname: string) {
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

function shouldUseSecureCookies(protocol: string, hostname: string) {
  if (protocol === "https:") return true;
  if (protocol === "http:") {
    if (isLoopbackHost(hostname)) {
      return false;
    }
    return false;
  }

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (siteUrl) {
    return siteUrl.startsWith("https");
  }

  return process.env.NODE_ENV === "production";
}

function buildCookieBase(request: NextRequest): Partial<CookieOptions> {
  return {
    httpOnly: true,
    secure: shouldUseSecureCookies(request.nextUrl.protocol, request.nextUrl.hostname),
    sameSite: "lax",
    path: "/",
  };
}

export async function proxy(request: NextRequest) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  // If Supabase isn't configured, let the request through
  // Server Components will handle auth validation
  if (!supabaseUrl || !supabaseKey) {
    return NextResponse.next();
  }

  const cookieBase = buildCookieBase(request);

  const response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  });

  // Create Supabase client for token refresh
  // This will automatically refresh expired tokens via the cookie adapter
  createServerClient(supabaseUrl, supabaseKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll().map(({ name, value }) => ({ name, value }));
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set({
            name,
            value,
            ...cookieBase,
            ...(options ?? {}),
          });
        });
      },
    },
    cookieOptions: cookieBase,
  });

  // No getUser() call - Server Components handle authentication
  // This proxy only ensures tokens are fresh
  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
