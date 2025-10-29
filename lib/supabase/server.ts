// lib/supabase/server.ts
import "server-only";
import { cookies } from "next/headers";
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import type { NextRequest, NextResponse } from "next/server";
import { ENV } from "@/lib/env";

const ONE_WEEK_SECONDS = 60 * 60 * 24 * 7;

function envPrefersSecureCookies() {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (siteUrl) {
    return siteUrl.startsWith("https");
  }
  return process.env.NODE_ENV === "production";
}

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

function resolveSecureFlag(protocol: string | undefined, hostname: string | undefined) {
  if (protocol === "https:") return true;
  if (protocol === "http:") {
    if (hostname && isLoopbackHost(hostname)) {
      return false;
    }
    return false;
  }
  if (hostname && isLoopbackHost(hostname)) return false;
  return envPrefersSecureCookies();
}

function buildCookieBase(): Partial<CookieOptions> {
  return {
    httpOnly: true,
    secure: envPrefersSecureCookies(),
    sameSite: "lax",
    path: "/",
    maxAge: ONE_WEEK_SECONDS,
  };
}

function buildCookieBaseForRequest(request: NextRequest): Partial<CookieOptions> {
  return {
    ...buildCookieBase(),
    secure: resolveSecureFlag(request.nextUrl.protocol, request.nextUrl.hostname),
  };
}

// Security defaults applied when we WRITE cookies (reading is unaffected)
const COOKIE_SECURITY_OPTIONS = buildCookieBase();

// Helper: Next.js throws when attempting to set cookies in RSC render phase
const isReadonlyCookiesError = (err: unknown) =>
  err instanceof Error &&
  err.message.includes("Cookies can only be modified in a Server Action or Route Handler");

/**
 * Server Components / Actions
 * - Uses new cookies adapter (getAll/setAll) to avoid deprecated signature
 * - Does NOT override cookie name; Supabase will use sb-<project-ref>-auth-token.*
 * - Safely ignores writes when running in a read-only context
 * - Creates fresh client per call to ensure proper user isolation (SECURITY)
 */
export async function createSupabaseServerClient() {
  const store = await cookies();

  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookies: {
      getAll() {
        // Read everything the browser sent
        return store.getAll().map(({ name, value }) => ({ name, value }));
      },
      setAll(cookiesToSet) {
        // Supabase returns all mutations it wants to perform
        for (const { name, value, options } of cookiesToSet) {
          try {
            store.set({
              name,
              value,
              ...COOKIE_SECURITY_OPTIONS,
              ...(options ?? {}),
            } as any);
          } catch (err) {
            if (!isReadonlyCookiesError(err)) {
              console.warn("[Supabase Server] Failed to set cookie:", name, err);
            }
          }
        }
      },
    },
  });
}

/**
 * Route Handlers (can write headers/cookies on the response)
 * - Use this inside app/api/* route handlers
 */
export function createSupabaseRouteHandlerClient(
  request: NextRequest,
  response: NextResponse
) {
  const base = buildCookieBaseForRequest(request);

  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookies: {
      getAll() {
        return request.cookies.getAll().map(({ name, value }) => ({ name, value }));
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set({
            name,
            value,
            ...base,
            ...(options ?? {}),
          } as any);
        }
      },
    },
  });
}
