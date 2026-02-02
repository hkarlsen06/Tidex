import type { NextRequest, NextResponse } from "next/server";
import { getAuthCookiePrefixes } from "./utils";

const LEGACY_COOKIE_NAMES = new Set(["sb-access-token", "sb-refresh-token"]);

/**
 * Force-remove all Supabase auth cookies from the response.
 * Useful when Supabase fails to clear cookies due to invalid refresh tokens.
 */
export function clearSupabaseAuthCookies(
  request: NextRequest,
  response: NextResponse
) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? null;
  const authCookiePrefixes = getAuthCookiePrefixes(supabaseUrl);

  const cookieNames = request.cookies
    .getAll()
    .map((cookie) => cookie.name)
    .filter((name) => {
      if (LEGACY_COOKIE_NAMES.has(name)) {
        return true;
      }

      return authCookiePrefixes.some((prefix) => name.startsWith(prefix));
    });

  if (cookieNames.length === 0) {
    return;
  }

  for (const name of cookieNames) {
    response.cookies.delete(name);
  }
}
