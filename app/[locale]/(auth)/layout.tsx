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

  // Redirect authenticated users to dashboard (unless they need MFA verification or terms acceptance)
  const session = await getSession();
  if (session) {
    // Check if user needs MFA verification
    const supabase = await createSupabaseServerClient();
    const { data: aalData } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();

    // If user has MFA enrolled (nextLevel is aal2) but hasn't verified (currentLevel is aal1),
    // they need to complete MFA - let them stay on auth pages (for mfa-verify)
    const needsMfaVerification = aalData?.currentLevel === "aal1" && aalData?.nextLevel === "aal2";

    // Check if user has accepted terms of service
    const termsAcceptedAt = session.user?.user_metadata?.terms_accepted_at;
    const needsTermsAcceptance = !termsAcceptedAt;

    // Check if user has completed onboarding
    const onboardingCompleted = session.user?.user_metadata?.onboarding_completed;
    const needsOnboarding = !onboardingCompleted;

    if (!needsMfaVerification && !needsTermsAcceptance && !needsOnboarding) {
      // User is fully authenticated, has accepted terms, and completed onboarding
      redirect(`/${locale}`);
    }
    // User needs MFA verification, terms acceptance, or onboarding - let them through to auth pages
  }

  const dictionary = getDictionary(locale as Locale);
  // Auth pages are always dark mode to match native iOS launch screen and prevent flash
  // Use inline style for background to ensure it's dark immediately (before CSS variables resolve)
  // The dark class enables dark mode CSS variables for child components
  return (
    <I18nProvider locale={locale as Locale} dictionary={dictionary} namespaces={['pages.auth']}>
      <div
        className="dark min-h-screen text-foreground antialiased"
        style={{ backgroundColor: 'hsl(222.2 84% 4.9%)' }}
      >
        <div className="app-container">
          <main className="flex min-h-screen flex-col items-center justify-center px-4 py-8">{children}</main>
        </div>
      </div>
    </I18nProvider>
  );
}
