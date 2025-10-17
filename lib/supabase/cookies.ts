import type { NextRequest, NextResponse } from "next/server";

import { SUPABASE_AUTH_COOKIE_NAME } from "./constants";

/**
 * Force-remove all Supabase auth cookies from the response.
 * Useful when Supabase fails to clear cookies due to invalid refresh tokens.
 */
export function clearSupabaseAuthCookies(
  request: NextRequest,
  response: NextResponse
) {
  const cookieNames = request.cookies
    .getAll()
    .map((cookie) => cookie.name)
    .filter((name) => name.startsWith(SUPABASE_AUTH_COOKIE_NAME));

  if (cookieNames.length === 0) {
    return;
  }

  for (const name of cookieNames) {
    response.cookies.delete(name);
  }
}
