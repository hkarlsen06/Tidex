import type { ReactNode } from "react";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getUserTheme } from "@/lib/theme/getTheme";

import { SupabaseListener } from "../supabase-listener";
import { TopHeader } from "@/components/app/TopHeader";
import { NavBar } from "@/components/app/NavBar";
import { ThemeProvider } from "@/components/app/ThemeProvider";

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

  // Get session for access token (used only for client-side auth state sync)
  const {
    data: { session },
  } = await supabase.auth.getSession();

  // Using verified user data from getUser() - safe for all server-side usage
  const userName =
    (user?.user_metadata?.full_name as string | undefined) ??
    (user?.user_metadata?.name as string | undefined) ??
    (user?.user_metadata?.display_name as string | undefined) ??
    user?.email ??
    "Guest";
  const avatarUrl =
    (user?.user_metadata?.avatar_url as string | undefined) ??
    (user?.user_metadata?.picture as string | undefined) ??
    null;

  // Get user's theme preference from database
  const serverTheme = await getUserTheme();

  return (
    <>
      <SupabaseListener accessToken={session?.access_token} />
      <ThemeProvider serverTheme={serverTheme} />
      <div className="app-container grid min-h-dvh grid-rows-[auto_1fr]">
        <TopHeader userName={userName} avatarUrl={avatarUrl} />
        <main className="px-4 pt-8" style={{ paddingBottom: 'calc(6rem + env(safe-area-inset-bottom))' }}>{children}</main>
        <NavBar />
      </div>
    </>
  );
}
