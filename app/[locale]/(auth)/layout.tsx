import type { Metadata } from "next";
import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { getDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";
import { getSession } from "@dal/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";

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
  // Opt out of prerendering - auth pages need dynamic session check
  connection();

  const { locale } = await params;

  // Redirect authenticated users to dashboard (unless they need MFA verification)
  const session = await getSession();
  if (session) {
    // Check if user needs MFA verification
    const supabase = await createSupabaseServerClient();
    const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

    // If user has MFA enrolled (nextLevel is aal2) but hasn't verified (currentLevel is aal1),
    // they need to complete MFA - redirect them to the MFA verify page
    const needsMfaVerification = aalData?.currentLevel === "aal1" && aalData?.nextLevel === "aal2";

    if (!needsMfaVerification) {
      // User is fully authenticated (no MFA or MFA already verified) - redirect to dashboard
      redirect(`/${locale}`);
    }
    // User needs MFA verification - let them through to auth pages (mfa-verify page will handle it)
    // Note: If they're on /login, the LoginClient will redirect them to /mfa-verify
  }

  const dictionary = getDictionary(locale as Locale);
  return (
    <I18nProvider locale={locale as Locale} dictionary={dictionary} namespaces={['pages.auth']}>
      <div className="min-h-screen bg-background text-foreground antialiased">
        <div className="app-container">
          <main className="flex min-h-screen flex-col items-center justify-center px-4 py-8">{children}</main>
        </div>
      </div>
    </I18nProvider>
  );
}
