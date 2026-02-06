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
  const loginUrl = `/${locale}/login`;

  // Create response with HTML that does client-side redirect.
  // Uses same background colors as the app (dark: #020817, light: #ffffff).
  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="0;url=${loginUrl}">
  <style>
    :root { --bg: #ffffff; }
    @media (prefers-color-scheme: dark) { :root { --bg: #020817; } }
    html, body { margin: 0; padding: 0; background-color: var(--bg); height: 100%; }
  </style>
  <script>
    // Check localStorage for theme preference (matches app's theme system)
    (function() {
      var theme = localStorage.getItem('theme');
      if (theme === 'dark' || (!theme && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
        document.documentElement.style.setProperty('--bg', '#020817');
      }
    })();
    window.location.href = "${loginUrl}";
  </script>
</head>
<body></body>
</html>`;

  const response = new NextResponse(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
    },
  });

  const supabase = createSupabaseRouteHandlerClient(request, response);

  // Get user ID before signing out (for cache invalidation)
  let userId: string | undefined;
  try {
    const { data } = await supabase.auth.getClaims();
    userId = data?.claims?.sub;
  } catch {
    // Ignore - user may already be logged out
  }

  // Sign out from Supabase with local scope (only clears this client's session)
  // This allows other devices to remain logged in
  try {
    await supabase.auth.signOut({ scope: "local" });
  } catch {
    // Ignore - user may already be logged out
  }

  // Always force-clear all auth cookies (belt and suspenders)
  clearSupabaseAuthCookies(request, response);

  // Clear cached user data
  if (userId) {
    try {
      revalidateTag(`user-${userId}`, "max");
    } catch {
      // Ignore cache invalidation errors
    }
  }

  return response;
}
