import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";

// Handle OAuth callbacks and magic link redirects
export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const next = requestUrl.searchParams.get("next") ?? "/";
  const redirectUrl = new URL(next, requestUrl.origin);
  const response = NextResponse.redirect(redirectUrl);

  if (code) {
    const supabase = createSupabaseRouteHandlerClient(request, response);
    await supabase.auth.exchangeCodeForSession(code);
  }

  return response;
}

// Handle client-side auth state changes and sync session to server cookies
export async function POST(request: NextRequest) {
  try {
    // CSRF and origin check: reject cross-site posts
    const origin = request.headers.get("origin");
    const requestOrigin = new URL(request.url).origin;
    const sameOrigin = origin && origin === requestOrigin;

    if (!sameOrigin || request.headers.get("x-csrf") !== "auth-sync") {
      console.warn("[AUTH SYNC] Rejected cross-site POST or missing CSRF token");
      return NextResponse.json({ ok: false }, { status: 403 });
    }

    const { event, session } = await request.json();
    const response = NextResponse.json({ ok: true });
    const supabase = createSupabaseRouteHandlerClient(request, response);

    if (session) {
      // Write the session into server-side cookies
      await supabase.auth.setSession(session);
    } else {
      // Clear cookies on sign-out
      await supabase.auth.signOut();
    }

    return response;
  } catch (error) {
    console.error("[AUTH SYNC] Failed to sync session to cookies:", error);
    return NextResponse.json({ ok: false }, { status: 500 });
  }
}

export const dynamic = "force-dynamic";
