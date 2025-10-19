// lib/supabase/server.ts
import "server-only";
import { cookies } from "next/headers";
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import type { NextRequest, NextResponse } from "next/server";
import { ENV } from "@/lib/env";

// Security defaults applied when we WRITE cookies (reading is unaffected)
const COOKIE_SECURITY_OPTIONS: Partial<CookieOptions> = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax",
  path: "/",
  maxAge: 60 * 60 * 24 * 7, // 7 days
};

// Helper: Next.js throws when attempting to set cookies in RSC render phase
const isReadonlyCookiesError = (err: unknown) =>
  err instanceof Error &&
  err.message.includes("Cookies can only be modified in a Server Action or Route Handler");

/**
 * Server Components / Actions
 * - Uses new cookies adapter (getAll/setAll) to avoid deprecated signature
 * - Does NOT override cookie name; Supabase will use sb-<project-ref>-auth-token.*
 * - Safely ignores writes when running in a read-only context
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
            ...COOKIE_SECURITY_OPTIONS,
            ...(options ?? {}),
          } as any);
        }
      },
    },
  });
}