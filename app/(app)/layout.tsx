import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Inter } from "next/font/google";

import { createSupabaseServerClient } from "@/lib/supabase/server";

import "../globals.css";
import { SupabaseListener } from "../supabase-listener";
import { TopHeader } from "../components/top-header";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "next-kkarlsen.dev",
  description: "Fresh Next.js project scaffolded by Codex",
};

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
    <html lang="en">
      <body className={`${inter.className} bg-slate-950 text-slate-100 antialiased`}>
        <SupabaseListener accessToken={session?.access_token} />
        <div className="app-container">
          <TopHeader userName={userName} avatarUrl={avatarUrl} />
          <main className="px-4 pb-10 pt-6">{children}</main>
        </div>
      </body>
    </html>
  );
}
