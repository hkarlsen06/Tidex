import "server-only";
import { cookies } from "next/headers";
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import type { NextRequest, NextResponse } from "next/server";
import { ENV } from "@/lib/env";
import { SUPABASE_AUTH_COOKIE_NAME } from "./constants";

// Secure cookie defaults for authentication
const COOKIE_SECURITY_OPTIONS: Partial<CookieOptions> = {
  httpOnly: true,
  // Secure flag only in production (requires HTTPS). In development (HTTP), secure cookies are rejected by browsers.
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax", // Use 'strict' if no cross-site OAuth flows
  maxAge: 60 * 60 * 24 * 7, // 7 days (matches Supabase default refresh token expiry)
  path: "/",
};

export async function createSupabaseServerClient() {
  const store = await cookies();
  const isWritableCookieStore =
    typeof store.set === "function" &&
    !Function.prototype.toString
      .call(store.set)
      .includes("ReadonlyRequestCookiesError");

  const mergeCookieOptions = (options?: CookieOptions) => {
    const merged = {
      ...COOKIE_SECURITY_OPTIONS,
      ...options,
    } as Record<string, unknown>;

    // Name is provided separately to cookies.set
    delete merged.name;
    return merged;
  };

  const shouldIgnoreCookieMutationError = (error: unknown) =>
    error instanceof Error &&
    error.message.includes("Cookies can only be modified in a Server Action or Route Handler");

  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookieOptions: {
      name: SUPABASE_AUTH_COOKIE_NAME,
      ...COOKIE_SECURITY_OPTIONS,
    },
    cookies: {
      get: (name: string) => store.get(name)?.value,
      set: (name: string, value: string, options?: CookieOptions) => {
        if (!isWritableCookieStore) {
          return;
        }

        try {
          store.set(name, value, mergeCookieOptions(options) as any);
        } catch (error) {
          if (!shouldIgnoreCookieMutationError(error)) {
            console.warn("[Supabase Server] Failed to set cookie:", name, error);
          }
        }
      },
      remove: (name: string, options?: CookieOptions) => {
        if (!isWritableCookieStore) {
          return;
        }

        try {
          const mergedOptions = mergeCookieOptions({
            ...options,
            expires: new Date(0),
            maxAge: 0,
          });

          store.set(name, "", mergedOptions as any);
        } catch (error) {
          if (!shouldIgnoreCookieMutationError(error)) {
            console.warn("[Supabase Server] Failed to remove cookie:", name, error);
          }
        }
      },
    },
  });
}

// For Route Handlers that need to set cookies on the response
export function createSupabaseRouteHandlerClient(
  request: NextRequest,
  response: NextResponse
) {
  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookieOptions: {
      name: SUPABASE_AUTH_COOKIE_NAME,
      ...COOKIE_SECURITY_OPTIONS,
    },
    cookies: {
      get: (name: string) => request.cookies.get(name)?.value,
      set: (name: string, value: string, options?: CookieOptions) => {
        // NextResponse supports both (name, value, options) and Cookie object
        response.cookies.set(name, value, {
          ...COOKIE_SECURITY_OPTIONS,
          ...options,
        } as any);
      },
      remove: (name: string, options?: CookieOptions) => {
        response.cookies.set(name, "", {
          ...COOKIE_SECURITY_OPTIONS,
          ...options,
          expires: new Date(0),
        } as any);
      },
    },
  });
}
