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

    const { error } = await supabase.auth.signOut({ scope: "local" });

    if (error) {
      clearSupabaseAuthCookies(request, response);
    }

    // Clear all cached user data if we have the userId
    if (userId) {
      try {
        revalidateTag(`user-${userId}`, 'max');
      } catch {
        // Ignore cache invalidation errors
      }
    }
  } catch {
    clearSupabaseAuthCookies(request, response);
  }

  return response;
}
