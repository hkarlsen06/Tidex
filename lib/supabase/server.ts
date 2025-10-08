import "server-only";
import { cookies } from "next/headers";
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import type { NextRequest, NextResponse } from "next/server";
import { ENV } from "@/lib/env";
import { SUPABASE_AUTH_COOKIE_NAME } from "./constants";

export async function createSupabaseServerClient() {
  const store = await cookies();
  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookieOptions: {
      name: SUPABASE_AUTH_COOKIE_NAME,
    },
    cookies: {
      get: (name: string) => store.get(name)?.value,
      set: (_n: string, _v: string, _o?: CookieOptions) => {},
      remove: (_n: string, _o?: CookieOptions) => {},
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
    },
    cookies: {
      get: (name: string) => request.cookies.get(name)?.value,
      set: (name: string, value: string, options?: CookieOptions) => {
        // NextResponse supports both (name, value, options) and Cookie object
        response.cookies.set(name, value, options as any);
      },
      remove: (name: string, _options?: CookieOptions) => {
        response.cookies.delete(name);
      },
    },
  });
}
