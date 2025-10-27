import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";
import { clearSupabaseAuthCookies } from "@/lib/supabase/cookies";

export async function GET(request: NextRequest) {
  const response = NextResponse.redirect(new URL("/login", request.url));
  const supabase = createSupabaseRouteHandlerClient(request, response);

  try {
    const { error } = await supabase.auth.signOut();

    if (error) {
      console.warn(
        "[AUTH LOGOUT] Supabase signOut returned error; clearing cookies manually",
        error
      );
      clearSupabaseAuthCookies(request, response);
    }
  } catch (error) {
    console.error("[AUTH LOGOUT] Unexpected signOut error; clearing cookies manually", error);
    clearSupabaseAuthCookies(request, response);
  }

  return response;
}
