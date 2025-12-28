import type { SupabaseClient } from "@supabase/supabase-js";
import { isNativePlatform } from "./platform";

type OAuthProvider = "google" | "apple";

interface OAuthOptions {
  redirectPath: string;
  queryParams?: Record<string, string>;
}

/**
 * Get the appropriate redirect URL for OAuth based on platform
 * - Native: tidex://auth/callback (custom scheme that app intercepts)
 * - Web: https://app.tidex.no/auth/callback (standard HTTPS)
 */
function getOAuthRedirectUrl(redirectPath: string): string {
  if (isNativePlatform()) {
    // Use custom scheme for native - the app will intercept this
    // and redirect to the HTTPS callback
    const url = new URL("tidex://auth/callback");
    url.searchParams.set("next", redirectPath);
    return url.toString();
  }

  // Web: use standard HTTPS callback
  const configuredBaseUrl = process.env.NEXT_PUBLIC_SITE_URL;
  const fallbackOrigin =
    typeof window !== "undefined" ? window.location.origin : undefined;
  const baseUrl =
    configuredBaseUrl && configuredBaseUrl.startsWith("http")
      ? configuredBaseUrl
      : fallbackOrigin;

  if (!baseUrl) {
    throw new Error("Unable to determine base URL for OAuth redirect");
  }

  const url = new URL("/auth/callback", baseUrl);
  url.searchParams.set("next", redirectPath);
  return url.toString();
}

/**
 * Perform OAuth sign-in handling both native and web platforms
 * - Native: Opens Capacitor Browser and returns the auth URL
 * - Web: Lets Supabase handle the redirect naturally
 *
 * @returns Object with success status and optional auth URL for native
 */
export async function performOAuthSignIn(
  supabase: SupabaseClient,
  provider: OAuthProvider,
  options: OAuthOptions
): Promise<{ success: boolean; error?: Error; authUrl?: string }> {
  try {
    const redirectTo = getOAuthRedirectUrl(options.redirectPath);

    const { data, error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo,
        skipBrowserRedirect: isNativePlatform(), // Don't auto-redirect on native
        queryParams: options.queryParams,
      },
    });

    if (error) {
      return { success: false, error };
    }

    if (isNativePlatform() && data.url) {
      // On native, open the auth URL in Capacitor Browser
      const { Browser } = await import("@capacitor/browser");
      await Browser.open({
        url: data.url,
        presentationStyle: "popover", // Use ASWebAuthenticationSession style
      });
      return { success: true, authUrl: data.url };
    }

    // On web, Supabase has already redirected
    return { success: true };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error : new Error(String(error)),
    };
  }
}
