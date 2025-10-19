import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

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

export const dynamic = "force-dynamic";
