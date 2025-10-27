import { NextResponse, type NextRequest } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";

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
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const oauthError = url.searchParams.get("error");
  const oauthErrorDesc = url.searchParams.get("error_description");
  const redirectUrl = resolveRedirectUrl(url);

  if (oauthError) {
    const login = new URL("/login", url.origin);
    login.searchParams.set("error", oauthErrorDesc ?? oauthError);
    return NextResponse.redirect(login);
  }

  const response = NextResponse.redirect(redirectUrl);

  if (!code) {
    return response;
  }

  const supabase = createSupabaseRouteHandlerClient(request, response);

  try {
    await supabase.auth.exchangeCodeForSession(code);
  } catch (error) {
    console.error("[AUTH CALLBACK] Failed to exchange code for session", error);
    const login = new URL("/login", url.origin);
    login.searchParams.set("error", "auth_exchange_failed");
    return NextResponse.redirect(login);
  }

  return response;
}
