import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { revalidateTag } from "next/cache";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";
import { clearSupabaseAuthCookies } from "@/lib/supabase/cookies";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ locale: string }> }
) {
  const { locale } = await params;
  const loginUrl = new URL(`/${locale}/login`, request.url);
  const response = NextResponse.redirect(loginUrl);
  const supabase = createSupabaseRouteHandlerClient(request, response);

  // Wrap all operations in a timeout to ensure we always respond quickly
  // This prevents the WebView from timing out and showing offline.html
  const logoutPromise = (async () => {
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
  })();

  // Wait for logout but with a timeout - if it takes too long, just return the redirect
  // The cookies will be cleared by the clearSupabaseAuthCookies fallback
  await Promise.race([
    logoutPromise,
    new Promise<void>((resolve) => setTimeout(resolve, 2000)) // 2 second timeout
  ]);

  return response;
}
