import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Inter } from "next/font/google";

import "./globals.css";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "next-kkarlsen.dev",
  description: "Fresh Next.js project scaffolded by Codex",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: `
              try {
                const theme = localStorage.getItem('theme') || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
                document.documentElement.classList.toggle('dark', theme === 'dark');
              } catch (e) {}
            `,
          }}
        />
      </head>
      <body className={`${inter.className} bg-background text-foreground antialiased`}>
        {children}
      </body>
    </html>
  );
}
