import { NextResponse, type NextRequest } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";
import { LOCALE_COOKIE, defaultLocale, locales, type Locale } from "@/lib/i18n/config";

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
  const nextParam = url.searchParams.get("next");
  const redirectUrl = resolveRedirectUrl(url);

  // Log all incoming params to debug the issue
  console.log("[AUTH CALLBACK] Incoming request:", {
    fullUrl: url.toString(),
    code: code ? "present" : "missing",
    isLinking,
    nextParam,
    redirectTo: redirectUrl.pathname,
  });

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
    // For identity linking, check if user already has a valid session BEFORE
    // exchanging the code. This prevents MFA bypass via forged linking=true param.
    // We check for AAL2 (MFA verified) OR AAL1 with nextLevel=AAL1 (no MFA enrolled).
    let wasAlreadyAuthenticated = false;
    if (isLinking) {
      const { data: preAuthAAL } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      // User is "already authenticated" if:
      // - AAL2: has MFA and verified it
      // - AAL1 with nextLevel AAL1: doesn't have MFA enrolled (fully authenticated)
      wasAlreadyAuthenticated = preAuthAAL?.currentLevel === 'aal2' ||
        (preAuthAAL?.currentLevel === 'aal1' && preAuthAAL?.nextLevel === 'aal1');

      console.log("[AUTH CALLBACK] Pre-exchange AAL check for linking:", {
        isLinking,
        currentLevel: preAuthAAL?.currentLevel,
        nextLevel: preAuthAAL?.nextLevel,
        wasAlreadyAuthenticated,
      });
    }

    const { data: sessionData } = await supabase.auth.exchangeCodeForSession(code);

    // Set locale cookie from user metadata if available
    const userLocale = sessionData?.user?.user_metadata?.locale;
    if (userLocale && locales.includes(userLocale as Locale)) {
      response.cookies.set(LOCALE_COOKIE, userLocale, {
        path: '/',
        sameSite: 'lax',
        maxAge: 60 * 60 * 24 * 365, // 1 year
      });
    }

    // Only skip MFA check if user was already fully authenticated before the OAuth flow
    // This prevents attackers from bypassing MFA by adding linking=true to login URLs
    if (!(isLinking && wasAlreadyAuthenticated)) {
      // Check if user needs MFA verification
      const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

      console.log("[AUTH CALLBACK] Post-exchange AAL check:", {
        isLinking,
        wasAlreadyAuthenticated,
        currentLevel: aalData?.currentLevel,
        nextLevel: aalData?.nextLevel,
      });

      if (aalData && aalData.currentLevel === 'aal1' && aalData.nextLevel === 'aal2') {
        // User has MFA enrolled but hasn't verified - redirect to MFA verify
        // Use user's saved locale preference from metadata, fall back to cookie or default
        const locale = (userLocale && locales.includes(userLocale as Locale) ? userLocale : null)
          || request.cookies.get(LOCALE_COOKIE)?.value
          || defaultLocale;
        const mfaUrl = new URL(`/${locale}/mfa-verify`, url.origin);

        // Build the next URL with proper locale prefix
        const localePattern = new RegExp(`^/(${locales.join('|')})(/|$)`);
        const hasLocalePrefix = localePattern.test(redirectUrl.pathname);
        let nextPath: string;
        if (hasLocalePrefix) {
          // Replace existing locale prefix
          nextPath = redirectUrl.pathname.replace(
            new RegExp(`^/(${locales.join('|')})`),
            `/${locale}`
          );
        } else {
          // Prepend locale
          nextPath = `/${locale}${redirectUrl.pathname}`;
        }
        mfaUrl.searchParams.set("next", nextPath + redirectUrl.search);

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
