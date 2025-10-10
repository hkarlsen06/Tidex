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
  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookieOptions: {
      name: SUPABASE_AUTH_COOKIE_NAME,
      ...COOKIE_SECURITY_OPTIONS,
    },
    cookies: {
      get: (name: string) => store.get(name)?.value,
      set: (name: string, value: string, options?: CookieOptions) => {
        try {
          store.set({ name, value, ...COOKIE_SECURITY_OPTIONS, ...options });
        } catch {
          // Ignore errors in Server Components (can't set cookies during render)
          // Cookie writes will succeed in Server Actions and Route Handlers
        }
      },
      remove: (name: string, options?: CookieOptions) => {
        try {
          store.set({
            name,
            value: "",
            ...COOKIE_SECURITY_OPTIONS,
            ...options,
            expires: new Date(0),
          });
        } catch {
          // Ignore errors in Server Components
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
