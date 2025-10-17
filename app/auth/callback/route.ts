import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";
import { AUTH_SYNC_CSRF_COOKIE_NAME, AUTH_SYNC_CSRF_HEADER } from "@/lib/auth/constants";
import { clearSupabaseAuthCookies } from "@/lib/supabase/cookies";

function resolveRedirectUrl(requestUrl: URL): URL {
  const nextParam = requestUrl.searchParams.get("next");

  if (!nextParam) {
    return new URL("/", requestUrl.origin);
  }

  try {
    const candidate = new URL(nextParam, requestUrl.origin);

    if (candidate.origin !== requestUrl.origin) {
      return new URL("/", requestUrl.origin);
    }

    return candidate;
  } catch (error) {
    console.warn("[AUTH CALLBACK] Invalid next parameter provided", {
      error,
      value: nextParam,
    });
    return new URL("/", requestUrl.origin);
  }
}

// Handle OAuth callbacks and magic link redirects
export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const redirectUrl = resolveRedirectUrl(requestUrl);
  const response = NextResponse.redirect(redirectUrl);

  if (code) {
    const supabase = createSupabaseRouteHandlerClient(request, response);

    try {
      await supabase.auth.exchangeCodeForSession(code);
    } catch (error) {
      console.error("[AUTH CALLBACK] Failed to exchange code for session", error);
      return NextResponse.redirect(new URL("/login", request.url));
    }
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

    const csrfHeader = request.headers.get(AUTH_SYNC_CSRF_HEADER);
    const csrfCookie = request.cookies.get(AUTH_SYNC_CSRF_COOKIE_NAME)?.value;

    if (!sameOrigin || !csrfHeader || !csrfCookie || csrfCookie !== csrfHeader) {
      console.warn("[AUTH SYNC] Rejected POST due to CSRF validation failure");
      return NextResponse.json({ ok: false }, { status: 403 });
    }

    const { event, session } = await request.json();
    const response = NextResponse.json({ ok: true });
    const supabase = createSupabaseRouteHandlerClient(request, response);

    if (session) {
      // Write the session into server-side cookies
      const { error: setSessionError } = await supabase.auth.setSession(session);

      if (setSessionError) {
        console.error("[AUTH SYNC] Failed to persist session cookie", setSessionError);
        const errorResponse = NextResponse.json(
          { ok: false },
          {
            status: 401,
            headers: { "cache-control": "no-store" },
          }
        );
        clearSupabaseAuthCookies(request, errorResponse);
        return errorResponse;
      }
    } else {
      // Clear cookies on sign-out
      const { error: signOutError } = await supabase.auth.signOut();

      if (signOutError) {
        console.warn(
          "[AUTH SYNC] Supabase signOut returned error; clearing cookies manually",
          signOutError
        );
        clearSupabaseAuthCookies(request, response);
      }
    }

    return response;
  } catch (error) {
    console.error("[AUTH SYNC] Failed to sync session to cookies:", error);
    return NextResponse.json({ ok: false }, { status: 500 });
  }
}

export const dynamic = "force-dynamic";
