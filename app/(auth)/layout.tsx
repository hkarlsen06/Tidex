import type { ReactNode } from "react";

// server component
export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <script
        dangerouslySetInnerHTML={{
          __html: `
            document.documentElement.classList.add('dark');
          `,
        }}
      />
      <div className="min-h-screen bg-background text-foreground antialiased">
        <div className="app-container">
          <main className="px-4 pb-24 pt-6">{children}</main>
        </div>
      </div>
    </>
  );
}
