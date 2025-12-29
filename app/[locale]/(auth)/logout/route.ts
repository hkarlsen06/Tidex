import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { revalidateTag } from "next/cache";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";
import { clearSupabaseAuthCookies } from "@/lib/supabase/cookies";

export async function GET(request: NextRequest) {
  const response = NextResponse.redirect(new URL("/login", request.url));
  const supabase = createSupabaseRouteHandlerClient(request, response);

  try {
    // Get user ID before signing out so we can clear their cache
    // Use getClaims() for performance - parses JWT locally without network request
    const { data } = await supabase.auth.getClaims();
    const userId = data?.claims?.sub;

    const { error } = await supabase.auth.signOut();

    if (error) {
      console.warn(
        "[AUTH LOGOUT] Supabase signOut returned error; clearing cookies manually",
        error
      );
      clearSupabaseAuthCookies(request, response);
    }

    // Clear all cached user data if we have the userId
    if (userId) {
      try {
        revalidateTag(`user-${userId}`, 'max');
        console.log(`[AUTH LOGOUT] Cleared cache for user ${userId}`);
      } catch (cacheError) {
        console.warn("[AUTH LOGOUT] Failed to clear user cache:", cacheError);
      }
    }
  } catch (error) {
    console.error("[AUTH LOGOUT] Unexpected signOut error; clearing cookies manually", error);
    clearSupabaseAuthCookies(request, response);
  }

  return response;
}
