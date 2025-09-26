import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Inter } from "next/font/google";

import { createSupabaseServerClient } from "@/lib/supabase/server";

import "./globals.css";
import { SupabaseListener } from "./supabase-listener";

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
  const supabase = createSupabaseServerClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  return (
    <html lang="en">
      <body className={`${inter.className} bg-slate-950 text-slate-100 antialiased`}>
        <SupabaseListener accessToken={session?.access_token} />
        {children}
      </body>
    </html>
  );
}
