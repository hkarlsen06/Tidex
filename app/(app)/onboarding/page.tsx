import { createSupabaseServerClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { OnboardingForm } from "./_components/OnboardingForm";

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

  return <OnboardingForm initialSettings={settings || undefined} />;
}
