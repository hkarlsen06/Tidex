// lib/supabase/server.ts
import "server-only";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import type { NextRequest, NextResponse } from "next/server";
import { ENV } from "@/lib/env";

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
 * - IMPORTANT: Uses Supabase's cookie options directly without overriding
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
        // Supabase returns all mutations it wants to perform with correct options
        for (const { name, value, options } of cookiesToSet) {
          try {
            store.set(name, value, options);
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
 * - IMPORTANT: Uses Supabase's cookie options directly without overriding
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
          response.cookies.set(name, value, options);
        }
      },
    },
  });
}
