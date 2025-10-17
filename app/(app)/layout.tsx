import type { ReactNode } from "react";
import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";
// import { getUserTheme } from "@/lib/theme/getTheme";
import { sanitizeDisplayName, sanitizeUrl } from "@/lib/sanitize";

import { SupabaseListener } from "../supabase-listener";
import { ThemeProvider } from "@/components/app/ThemeProvider";
import { MonthProvider } from "@/components/app/MonthContext";
import { AppLayoutClient } from "@/components/app/AppLayoutClient";

// Server layout: Uses verified user data from getUser() for secure UI rendering.
// Child pages that need authorization must also call auth.getUser() themselves.
export default async function RootLayout({
  children,
}: {
  children: ReactNode;
}) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Redirect to login if no valid session
  if (!user) {
    redirect("/login");
  }

  // Run subsequent queries in parallel to minimize latency
  const [sessionRes, settingsRes, shiftCountRes] = await Promise.all([
    supabase.auth.getSession(),
    supabase
      .from("user_settings")
      .select("profile_picture_url,theme")
      .eq("user_id", user.id)
      .maybeSingle(),
    supabase
      .from("user_shifts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id),
  ]);

  const {
    data: { session },
  } = sessionRes;

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

  const { data: settings } = settingsRes;
  const profilePictureUrl = sanitizeUrl(settings?.profile_picture_url ?? null);
  const resolvedAvatarUrl = profilePictureUrl ?? avatarUrl;

  const { count: shiftCount, error: shiftCountError } = shiftCountRes;
  const showAddShiftHint = !shiftCountError && (shiftCount ?? 0) === 0;

  // Resolve user's theme preference from already-fetched settings
  const serverTheme =
    settings?.theme === "light" || settings?.theme === "dark" || settings?.theme === "system"
      ? (settings.theme as "light" | "dark" | "system")
      : null;

  return (
    <ThemeProvider serverTheme={serverTheme}>
      <MonthProvider>
        <SupabaseListener accessToken={session?.access_token} />
        <AppLayoutClient
          userName={userName}
          avatarUrl={resolvedAvatarUrl}
          showAddShiftHint={showAddShiftHint}
        >
          {children}
        </AppLayoutClient>
      </MonthProvider>
    </ThemeProvider>
  );
}
