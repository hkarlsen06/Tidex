import type { Metadata } from "next";
import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { getDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";
import { getSession } from "@dal/auth";

export const metadata: Metadata = {
  manifest: "/manifest.json",
};

// server component
export default async function AuthLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;

  // Redirect authenticated users to dashboard
  const session = await getSession();
  if (session) {
    redirect(`/${locale}`);
  }

  const dictionary = getDictionary(locale as Locale);
  return (
    <I18nProvider locale={locale as Locale} dictionary={dictionary} namespaces={['pages.auth']}>
      <div className="min-h-screen bg-background text-foreground antialiased">
        <div className="app-container">
          <main className="px-4 pb-24 pt-6">{children}</main>
        </div>
      </div>
    </I18nProvider>
  );
}
