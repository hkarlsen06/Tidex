import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
// import { getUserTheme } from "@/lib/theme/getTheme";
import { sanitizeDisplayName, sanitizeUrl } from "@/lib/sanitize";

import { SupabaseListener } from "@/app/supabase-listener";
import { ThemeProvider } from "@/components/app/ThemeProvider";
import { MonthProvider } from "@/components/app/MonthContext";
import { AppLayoutClient } from "@/components/app/AppLayoutClient";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { CurrencyProvider } from "@/components/providers/CurrencyProvider";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";

/**
 * Protected App Layout
 *
 * This layout enforces authentication for all routes under (app)/.
 * Following Next.js 16 best practices, authentication happens in Server Components
 * (the data access layer), not in proxy.ts.
 *
 * Unauthenticated users are redirected to /login.
 * Users with pending MFA verification are redirected to /mfa-verify.
 */
export default async function RootLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Authentication enforcement - redirect to login if no user
  if (!user) {
    redirect("/login");
  }

  // MFA enforcement - redirect to MFA verify if user has enrolled but not verified
  const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aalData?.currentLevel === "aal1" && aalData?.nextLevel === "aal2") {
    redirect(`/${locale}/mfa-verify`);
  }

  // Fetch user settings
  // IMPORTANT: Do NOT call getSession() on the server side
  // Reason: getSession() can trigger token refresh network calls, which can cause
  // "Refresh Token Not Found" errors when racing with:
  // 1. Proxy token refresh in proxy.ts
  // 2. Client-side session checks in SupabaseListener and AppLayoutClient
  // 3. Service worker background operations
  // Server-side should ONLY use getUser() for auth validation.
  const { data: settings } = await supabase
    .from("user_settings")
    .select("profile_picture_url,theme,currency")
    .eq("user_id", user.id)
    .maybeSingle();

  // Sanitize user metadata from OAuth providers for defense-in-depth
  const rawUserName =
    (user.user_metadata?.first_name as string | undefined) ??
    (user.user_metadata?.full_name as string | undefined) ??
    (user.user_metadata?.name as string | undefined) ??
    (user.user_metadata?.display_name as string | undefined) ??
    user.email ??
    "User";
  const userName = sanitizeDisplayName(rawUserName);

  const rawMetadataAvatarUrl =
    (user.user_metadata?.avatar_url as string | undefined) ??
    (user.user_metadata?.picture as string | undefined) ??
    null;
  const metadataAvatarUrl = sanitizeUrl(rawMetadataAvatarUrl);

  const rawIdentityAvatarUrl = (() => {
    if (!user.identities || user.identities.length === 0) {
      return null;
    }

    for (const identity of user.identities) {
      const data = identity.identity_data as Record<string, unknown> | null | undefined;
      if (!data) continue;

      const candidate =
        (typeof data.avatar_url === "string" && data.avatar_url) ||
        (typeof data.picture === "string" && data.picture) ||
        null;

      if (candidate) {
        return candidate;
      }
    }

    return null;
  })();

  const identityAvatarUrl = sanitizeUrl(rawIdentityAvatarUrl);

  const avatarUrl = metadataAvatarUrl ?? identityAvatarUrl;
  const profilePictureUrl = sanitizeUrl(settings?.profile_picture_url ?? null);
  const resolvedAvatarUrl = profilePictureUrl ?? avatarUrl;

  // Resolve user's theme preference from already-fetched settings
  const serverTheme =
    settings?.theme === "light" || settings?.theme === "dark" || settings?.theme === "system"
      ? (settings.theme as "light" | "dark" | "system")
      : null;

  // Provide a trimmed dictionary for the authenticated app shell.
  const appDictionary = getAppDictionary(locale as Locale, []);

  return (
    <ThemeProvider serverTheme={serverTheme}>
      <MonthProvider>
        <CurrencyProvider currency={settings?.currency ?? "kr"}>
          <I18nProvider locale={locale as Locale} dictionary={appDictionary} namespaces={[]}>
            <SupabaseListener />
            <AppLayoutClient userName={userName} avatarUrl={resolvedAvatarUrl}>
              {children}
            </AppLayoutClient>
          </I18nProvider>
        </CurrencyProvider>
      </MonthProvider>
    </ThemeProvider>
  );
}
