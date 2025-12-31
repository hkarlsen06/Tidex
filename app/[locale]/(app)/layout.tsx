import type { ReactNode } from "react";
import { Suspense } from "react";
import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { sanitizeDisplayName, sanitizeUrl } from "@/lib/sanitize";

import { SupabaseListener } from "@/app/supabase-listener";
import { ThemeProvider } from "@/components/app/ThemeProvider";
import { MonthProvider } from "@/components/app/MonthContext";
import { AppLayoutClient } from "@/components/app/AppLayoutClient";
import { SharersProvider } from "@/components/app/SharersProvider";
import { UserAvatarProvider } from "@/components/app/UserAvatarProvider";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { CurrencyProvider } from "@/components/providers/CurrencyProvider";
import { PushNotificationProvider } from "@/components/providers/PushNotificationProvider";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import { getUsersWhoSharedWithMe } from "@/data-access/sharing";
import type { Locale } from "@/lib/i18n/config";

/**
 * Async server component that fetches sharers data and streams it to the client
 */
async function SharersData({ userId, children }: { userId: string; children: ReactNode }) {
  const sharers = await getUsersWhoSharedWithMe(userId);
  return <SharersProvider sharers={sharers}>{children}</SharersProvider>;
}

/**
 * Async server component that fetches user settings (profile picture, currency) and streams to client
 */
async function UserSettingsData({
  userId,
  oauthAvatarUrl,
  children,
}: {
  userId: string;
  oauthAvatarUrl: string | null;
  children: ReactNode;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: settings } = await supabase
    .from("user_settings")
    .select("profile_picture_url,currency")
    .eq("user_id", userId)
    .maybeSingle();

  const profilePictureUrl = sanitizeUrl(settings?.profile_picture_url ?? null);
  const resolvedAvatarUrl = profilePictureUrl ?? oauthAvatarUrl;
  const currency = settings?.currency ?? "kr";

  return (
    <CurrencyProvider currency={currency}>
      <UserAvatarProvider avatarUrl={resolvedAvatarUrl}>{children}</UserAvatarProvider>
    </CurrencyProvider>
  );
}

/**
 * Protected App Layout
 *
 * This layout enforces authentication for all routes under (app)/.
 * Following Next.js 16 best practices, authentication happens in Server Components
 * (the data access layer), not in proxy.ts.
 *
 * Uses getClaims() for performance - parses JWT locally without network request.
 * See: https://supabase.com/docs/reference/javascript/auth-getclaims
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

  // Use getClaims() for performance - parses JWT locally without network request
  const { data, error } = await supabase.auth.getClaims();

  // Authentication enforcement - redirect to login if no valid session
  if (error || !data?.claims) {
    redirect("/login");
  }

  const claims = data.claims;

  // MFA enforcement - redirect to MFA verify if user has enrolled but not verified
  // Note: MFA AAL info is available in claims.aal
  const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aalData?.currentLevel === "aal1" && aalData?.nextLevel === "aal2") {
    // Get the current path from proxy header to redirect back after MFA verification
    const headersList = await headers();
    const currentPath = headersList.get("x-current-path") || `/${locale}`;
    const mfaUrl = `/${locale}/mfa-verify?next=${encodeURIComponent(currentPath)}`;
    redirect(mfaUrl);
  }

  // Extract user metadata from JWT claims (available in user_metadata)
  const userMetadata = claims.user_metadata ?? {};
  const rawUserName =
    (userMetadata.full_name as string | undefined) ??
    (userMetadata.name as string | undefined) ??
    (userMetadata.display_name as string | undefined) ??
    claims.email ??
    "User";
  const userName = sanitizeDisplayName(rawUserName);

  // Get OAuth avatar URL from user_metadata (available in JWT claims)
  // Note: identities array is not available in claims, only in full User object
  // user_metadata typically contains avatar_url from OAuth providers
  const rawMetadataAvatarUrl =
    (userMetadata.avatar_url as string | undefined) ??
    (userMetadata.picture as string | undefined) ??
    null;
  const oauthAvatarUrl = sanitizeUrl(rawMetadataAvatarUrl);

  // Provide a trimmed dictionary for the authenticated app shell.
  const appDictionary = getAppDictionary(locale as Locale, []);

  return (
    <ThemeProvider>
      <MonthProvider>
        <I18nProvider locale={locale as Locale} dictionary={appDictionary} namespaces={[]}>
          <SupabaseListener />
          <PushNotificationProvider>
          {/* Stream user settings (currency, avatar) with Suspense */}
          <Suspense
            fallback={
              <CurrencyProvider currency="kr">
                <SharersProvider sharers={[]}>
                  <AppLayoutClient userName={userName}>{children}</AppLayoutClient>
                </SharersProvider>
              </CurrencyProvider>
            }
          >
            <UserSettingsData userId={claims.sub} oauthAvatarUrl={oauthAvatarUrl}>
              {/* Stream sharers data separately - SharersProvider in fallback prevents layout shift */}
              <Suspense
                fallback={
                  <SharersProvider sharers={[]}>
                    <AppLayoutClient userName={userName}>{children}</AppLayoutClient>
                  </SharersProvider>
                }
              >
                <SharersData userId={claims.sub}>
                  <AppLayoutClient userName={userName}>{children}</AppLayoutClient>
                </SharersData>
              </Suspense>
            </UserSettingsData>
          </Suspense>
          </PushNotificationProvider>
        </I18nProvider>
      </MonthProvider>
    </ThemeProvider>
  );
}
