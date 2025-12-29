import { createSupabaseServerClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { OnboardingForm } from "./_components/OnboardingForm";
import { getSnapshotForDate } from "@/data-access/wage-snapshots";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";

export const metadata: Metadata = {
  title: "Kom i gang",
};

export default async function OnboardingPage({
  params,
}: {
  params: Promise<{ locale: Locale }>;
}) {
  const { locale } = await params;
  const dictionary = getAppDictionary(locale, ['onboarding']);

  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();

  // Use getClaims() for performance - parses JWT locally without network request
  const { data, error } = await supabase.auth.getClaims();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (error || !data?.claims) {
    redirect("/login");
  }

  const claims = data.claims;

  // Check if user has already completed onboarding (from user_metadata in JWT)
  const finishedOnboarding = claims.user_metadata?.finishedOnboarding;
  if (finishedOnboarding) {
    redirect("/");
  }

  // Load existing settings (if any)
  const { data: settings } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", claims.sub)
    .single();

  // Load current wage snapshot if it exists (for users restarting onboarding)
  const today = new Date().toISOString().split('T')[0];
  const currentSnapshot = await getSnapshotForDate(today);

  // Merge settings with wage snapshot data
  const initialSettings = {
    ...settings,
    ...(currentSnapshot && {
      use_preset: currentSnapshot.wage_level !== null,
      current_wage_level: currentSnapshot.wage_level,
      custom_wage: currentSnapshot.hourly_wage,
      custom_supplements: currentSnapshot.wage_level === null ? currentSnapshot.supplements : null,
    }),
  };

  return (
    <I18nProvider locale={locale} dictionary={dictionary} namespaces={['onboarding']}>
      <OnboardingForm initialSettings={initialSettings || undefined} />
    </I18nProvider>
  );
}
