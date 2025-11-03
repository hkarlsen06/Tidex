import type { Metadata } from "next";
import type { ReactNode } from "react";

export const metadata: Metadata = {
  manifest: "/manifest.json",
  robots: {
    index: true,
    follow: true,
  },
};

// server component
export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen bg-background text-foreground antialiased">
      <div className="app-container">
        <main className="px-4 pb-24 pt-6">{children}</main>
      </div>
    </div>
  );
}
