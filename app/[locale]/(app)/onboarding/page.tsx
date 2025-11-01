import { createSupabaseServerClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { OnboardingForm } from "./_components/OnboardingForm";
import { getSnapshotForDate } from "@/data-access/wage-snapshots";

export const metadata: Metadata = {
  title: "Kom i gang",
};

export default async function OnboardingPage() {
  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();

  // Get current user
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect("/login");
  }

  // Check if user has already completed onboarding
  const finishedOnboarding = user.user_metadata?.finishedOnboarding;
  if (finishedOnboarding) {
    redirect("/");
  }

  // Load existing settings (if any)
  const { data: settings } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", user.id)
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

  return <OnboardingForm initialSettings={initialSettings || undefined} />;
}
