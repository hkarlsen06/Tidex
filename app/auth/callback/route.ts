import { NextResponse, type NextRequest } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";
import { LOCALE_COOKIE, defaultLocale } from "@/lib/i18n/config";

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
  const isLinking = url.searchParams.get("linking") === "true";
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
    // For identity linking, check if user already has a valid AAL2 session BEFORE
    // exchanging the code. This prevents MFA bypass via forged linking=true param.
    let wasAlreadyAuthenticated = false;
    if (isLinking) {
      const { data: preAuthAAL } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      wasAlreadyAuthenticated = preAuthAAL?.currentLevel === 'aal2';
    }

    await supabase.auth.exchangeCodeForSession(code);

    // Only skip MFA check if user was already authenticated at AAL2 before the OAuth flow
    // This prevents attackers from bypassing MFA by adding linking=true to login URLs
    if (!(isLinking && wasAlreadyAuthenticated)) {
      // Check if user needs MFA verification
      const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

      if (aalData && aalData.currentLevel === 'aal1' && aalData.nextLevel === 'aal2') {
        // User has MFA enrolled but hasn't verified - redirect to MFA verify
        const locale = request.cookies.get(LOCALE_COOKIE)?.value || defaultLocale;
        const mfaUrl = new URL(`/${locale}/mfa-verify`, url.origin);
        mfaUrl.searchParams.set("next", redirectUrl.pathname + redirectUrl.search);

        // Create new redirect but copy cookies from original response
        const mfaResponse = NextResponse.redirect(mfaUrl);
        response.cookies.getAll().forEach((cookie) => {
          mfaResponse.cookies.set(cookie.name, cookie.value, {
            ...cookie,
          });
        });
        return mfaResponse;
      }
    }
  } catch (error) {
    console.error("[AUTH CALLBACK] Failed to exchange code for session", error);
    const login = new URL("/login", url.origin);
    login.searchParams.set("error", "auth_exchange_failed");
    return NextResponse.redirect(login);
  }

  return response;
}
