import type { ReactNode } from "react";

export default function OAuthConsentLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen bg-background text-foreground antialiased">
      <div className="app-container">
        <main className="flex min-h-screen flex-col items-center justify-center px-4 py-8 pt-[calc(env(safe-area-inset-top)+2rem)]">
          {children}
        </main>
      </div>
    </div>
  );
}
