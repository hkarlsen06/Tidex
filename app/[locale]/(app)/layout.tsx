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
import { ImpersonationProvider } from "@/components/providers/ImpersonationProvider";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import { getUsersWhoSharedWithMe } from "@/data-access/sharing";
import {
  readImpersonationContext,
  validateTargetUser,
  getImpersonationSession,
} from "@/lib/auth/impersonation";
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
    redirect(`/${locale}/login`);
  }

  const claims = data.claims;

  // Check for active impersonation session BEFORE MFA check
  // Security layers preventing MFA bypass via fake cookie:
  // 1. Cookie is cryptographically signed with HMAC-SHA256 (secret key required)
  // 2. We verify the session exists in the database AND hasn't expired/ended
  // 3. The admin already passed MFA when they logged in
  // 4. Session ID in cookie must match an active database record
  // 5. Current authenticated user must match the target user in the session (verified below)
  let impersonationContext = await readImpersonationContext();

  // Validate impersonation session exists in database (defense in depth)
  // This prevents any theoretical cookie forgery even if signing key leaked
  if (impersonationContext) {
    const session = await getImpersonationSession(impersonationContext.impersonationSessionId);
    const now = new Date();

    // Session must exist, not be ended, not be expired, AND current user must match target user
    // The user match check is critical to prevent MFA bypass if cookie is somehow forged
    if (
      !session ||
      session.ended_at !== null ||
      new Date(session.expires_at) < now ||
      impersonationContext.targetUserId !== claims.sub
    ) {
      // Invalid, expired, or mismatched session - clear context (cookie cleanup happens in proxy)
      impersonationContext = null;
    }
  }

  // MFA enforcement - redirect to MFA verify if user has enrolled but not verified
  // Skip MFA check if impersonating - the admin has already authenticated with MFA
  // Note: MFA AAL info is available in claims.aal
  const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (
    aalData?.currentLevel === "aal1" &&
    aalData?.nextLevel === "aal2" &&
    !impersonationContext // Skip MFA redirect when impersonating
  ) {
    // Get the current path from proxy header to redirect back after MFA verification
    const headersList = await headers();
    const currentPath = headersList.get("x-current-path") || `/${locale}`;
    const mfaUrl = `/${locale}/mfa-verify?next=${encodeURIComponent(currentPath)}`;
    redirect(mfaUrl);
  }

  // Extract user metadata from JWT claims (available in user_metadata)
  // Use || instead of ?? to also fall through on empty strings (e.g., when user clears their name)
  const userMetadata = claims.user_metadata ?? {};
  const rawUserName =
    (userMetadata.full_name as string | undefined) ||
    (userMetadata.name as string | undefined) ||
    (userMetadata.display_name as string | undefined) ||
    claims.email ||
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

  // Prepare impersonation banner data (context was already validated above including user match)
  let impersonationBannerData: {
    targetUserName: string | null;
    adminUserId: string;
    expiresAt: string;
  } | null = null;

  if (impersonationContext) {
    // User match was already verified above in the database validation block
    // Fetch target user's display name for the banner
    const targetValidation = await validateTargetUser(impersonationContext.targetUserId);
    impersonationBannerData = {
      targetUserName: targetValidation.displayName ?? targetValidation.email ?? userName,
      adminUserId: impersonationContext.adminUserId,
      expiresAt: impersonationContext.expiresAt,
    };
  }

  // Provide a trimmed dictionary for the authenticated app shell.
  const appDictionary = getAppDictionary(locale as Locale, []);

  // Determine if we're impersonating (for context provider)
  const isImpersonating = impersonationBannerData !== null;

  return (
    <ThemeProvider>
      <MonthProvider>
        <I18nProvider locale={locale as Locale} dictionary={appDictionary} namespaces={[]}>
          <ImpersonationProvider
            isImpersonating={isImpersonating}
            targetUserId={impersonationContext?.targetUserId}
            adminUserId={impersonationContext?.adminUserId}
            targetUserName={impersonationBannerData?.targetUserName ?? undefined}
            expiresAt={impersonationBannerData?.expiresAt}
          >
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
          </ImpersonationProvider>
        </I18nProvider>
      </MonthProvider>
    </ThemeProvider>
  );
}
