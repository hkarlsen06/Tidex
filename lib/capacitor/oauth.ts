import type { SupabaseClient } from "@supabase/supabase-js";
import { isNativePlatform, isIOSPlatform } from "./platform";

type OAuthProvider = "google" | "apple";

// iOS Google Client ID from Google Cloud Console
const GOOGLE_IOS_CLIENT_ID =
  "496501907923-a0sng8rs2gscdu2fdenlq4j2g8vq9gas.apps.googleusercontent.com";

/**
 * Generate a random nonce for OAuth flows
 */
function generateNonce(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join(
    ""
  );
}

/**
 * Perform native Google Sign-in on iOS using the native Google Sign-In SDK.
 * This shows a bottom sheet with Google accounts instead of opening a browser.
 */
async function performNativeGoogleSignIn(
  supabase: SupabaseClient
): Promise<{ success: boolean; error?: Error }> {
  try {
    const { SocialLogin } = await import("@capgo/capacitor-social-login");

    // Initialize Google provider with iOS Client ID
    await SocialLogin.initialize({
      google: {
        iOSClientId: GOOGLE_IOS_CLIENT_ID,
      },
    });

    // Generate nonce for token verification
    const nonce = generateNonce();

    // Trigger native Google Sign-in with nonce
    const result = await SocialLogin.login({
      provider: "google",
      options: {
        scopes: ["email", "profile"],
        nonce,
      },
    });

    // Google returns idToken for online mode
    if (result.result && "idToken" in result.result && result.result.idToken) {
      // Exchange the ID token with Supabase, including the nonce
      const { error } = await supabase.auth.signInWithIdToken({
        provider: "google",
        token: result.result.idToken,
        nonce,
      });

      if (error) {
        return { success: false, error };
      }

      return { success: true };
    }

    return {
      success: false,
      error: new Error("No ID token received from Google"),
    };
  } catch (error) {
    // User cancelled or other error
    return {
      success: false,
      error: error instanceof Error ? error : new Error(String(error)),
    };
  }
}

/**
 * Perform native Apple Sign-in on iOS using the native Sign in with Apple prompt.
 * This avoids the white overlay browser issue and respects system dark mode.
 */
async function performNativeAppleSignIn(
  supabase: SupabaseClient
): Promise<{ success: boolean; error?: Error }> {
  try {
    const { SocialLogin } = await import("@capgo/capacitor-social-login");

    // Initialize Apple provider (no config needed on iOS - uses bundle ID)
    await SocialLogin.initialize({
      apple: {},
    });

    // Trigger native Apple Sign-in prompt
    const result = await SocialLogin.login({
      provider: "apple",
      options: {
        scopes: ["email", "name"],
      },
    });

    if (!result.result?.idToken) {
      return {
        success: false,
        error: new Error("No identity token received from Apple"),
      };
    }

    // Exchange the identity token with Supabase
    const { error } = await supabase.auth.signInWithIdToken({
      provider: "apple",
      token: result.result.idToken,
    });

    if (error) {
      return { success: false, error };
    }

    return { success: true };
  } catch (error) {
    // User cancelled or other error
    return {
      success: false,
      error: error instanceof Error ? error : new Error(String(error)),
    };
  }
}

interface OAuthOptions {
  redirectPath: string;
  queryParams?: Record<string, string>;
}

interface LinkIdentityOptions {
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
 * - iOS + Apple: Uses native Sign in with Apple (no white overlay)
 * - Other native: Opens Capacitor Browser
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
    // Use native sign-in on iOS to avoid white overlay browser
    if (isIOSPlatform()) {
      if (provider === "apple") {
        return await performNativeAppleSignIn(supabase);
      }
      if (provider === "google") {
        return await performNativeGoogleSignIn(supabase);
      }
    }

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

/**
 * Get the appropriate redirect URL for identity linking based on platform
 * Similar to getOAuthRedirectUrl but includes the 'linking=true' param
 * - Native: tidex://auth/callback?linking=true (custom scheme that app intercepts)
 * - Web: https://app.tidex.no/auth/callback?linking=true (standard HTTPS)
 */
function getLinkIdentityRedirectUrl(redirectPath: string): string {
  if (isNativePlatform()) {
    // Use custom scheme for native - the app will intercept this
    // and redirect to the HTTPS callback
    const url = new URL("tidex://auth/callback");
    url.searchParams.set("next", redirectPath);
    url.searchParams.set("linking", "true");
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
    throw new Error("Unable to determine base URL for identity link redirect");
  }

  const url = new URL("/auth/callback", baseUrl);
  url.searchParams.set("next", redirectPath);
  url.searchParams.set("linking", "true");
  return url.toString();
}

/**
 * Perform identity linking handling both native and web platforms
 * - Native: Opens Capacitor Browser and returns the auth URL
 * - Web: Returns the URL for client to navigate to
 *
 * This is used for linking additional OAuth providers to an existing account.
 * Unlike performOAuthSignIn, this uses linkIdentity instead of signInWithOAuth.
 *
 * @returns Object with success status, optional auth URL, and error
 */
export async function performIdentityLink(
  supabase: SupabaseClient,
  provider: OAuthProvider,
  options: LinkIdentityOptions
): Promise<{ success: boolean; error?: Error; authUrl?: string }> {
  try {
    const redirectTo = getLinkIdentityRedirectUrl(options.redirectPath);

    const { data, error } = await supabase.auth.linkIdentity({
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

    // On web, return the URL for the client to navigate to
    if (data.url) {
      return { success: true, authUrl: data.url };
    }

    return { success: true };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error : new Error(String(error)),
    };
  }
}
