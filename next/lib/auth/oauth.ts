import type { SupabaseClient } from "@supabase/supabase-js";

type OAuthProvider = "google" | "apple";

interface OAuthOptions {
  redirectPath: string;
  queryParams?: Record<string, string>;
}

interface LinkIdentityOptions {
  redirectPath: string;
  queryParams?: Record<string, string>;
}

function getBaseUrl(): string {
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

  return baseUrl;
}

function getOAuthRedirectUrl(redirectPath: string): string {
  const url = new URL("/auth/callback", getBaseUrl());
  url.searchParams.set("next", redirectPath);
  return url.toString();
}

function getLinkIdentityRedirectUrl(redirectPath: string): string {
  const url = new URL("/auth/callback", getBaseUrl());
  url.searchParams.set("next", redirectPath);
  url.searchParams.set("linking", "true");
  return url.toString();
}

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
        skipBrowserRedirect: true,
        queryParams: options.queryParams,
      },
    });

    if (error) {
      return { success: false, error };
    }

    if (!data.url) {
      return { success: false, error: new Error("No auth URL returned") };
    }

    if (typeof window !== "undefined") {
      window.location.href = data.url;
    }

    return { success: true, authUrl: data.url };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error : new Error(String(error)),
    };
  }
}

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
        skipBrowserRedirect: true,
        queryParams: options.queryParams,
      },
    });

    if (error) {
      return { success: false, error };
    }

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
