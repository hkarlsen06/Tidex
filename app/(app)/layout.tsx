import type { ReactNode } from "react";

import { createSupabaseServerClient } from "@/lib/supabase/server";

import { SupabaseListener } from "../supabase-listener";
import { TopHeader } from "../../components/app/TopHeader";

export default async function RootLayout({
  children,
}: {
  children: ReactNode;
}) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  const {
    data: { user },
  } = await supabase.auth.getUser();
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

  return (
    <>
      <SupabaseListener accessToken={session?.access_token} />
      <div className="app-container">
        <TopHeader userName={userName} avatarUrl={avatarUrl} />
        <main className="px-4 pb-10 pt-6">{children}</main>
      </div>
    </>
  );
}
