import type { ReactNode } from "react";
import { Suspense } from "react";
import { redirect } from "next/navigation";
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

  // Extract user metadata from OAuth providers (available immediately, no DB call)
  const rawUserName =
    (user.user_metadata?.first_name as string | undefined) ??
    (user.user_metadata?.full_name as string | undefined) ??
    (user.user_metadata?.name as string | undefined) ??
    (user.user_metadata?.display_name as string | undefined) ??
    user.email ??
    "User";
  const userName = sanitizeDisplayName(rawUserName);

  // Get OAuth avatar URL for fallback (available immediately from auth metadata)
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
  const oauthAvatarUrl = metadataAvatarUrl ?? identityAvatarUrl;

  // Provide a trimmed dictionary for the authenticated app shell.
  const appDictionary = getAppDictionary(locale as Locale, []);

  return (
    <ThemeProvider>
      <MonthProvider>
        <I18nProvider locale={locale as Locale} dictionary={appDictionary} namespaces={[]}>
          <SupabaseListener />
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
            <UserSettingsData userId={user.id} oauthAvatarUrl={oauthAvatarUrl}>
              {/* Stream sharers data separately - SharersProvider in fallback prevents layout shift */}
              <Suspense
                fallback={
                  <SharersProvider sharers={[]}>
                    <AppLayoutClient userName={userName}>{children}</AppLayoutClient>
                  </SharersProvider>
                }
              >
                <SharersData userId={user.id}>
                  <AppLayoutClient userName={userName}>{children}</AppLayoutClient>
                </SharersData>
              </Suspense>
            </UserSettingsData>
          </Suspense>
        </I18nProvider>
      </MonthProvider>
    </ThemeProvider>
  );
}
