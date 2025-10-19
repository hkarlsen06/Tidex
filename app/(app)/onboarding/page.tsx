import { createSupabaseServerClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { OnboardingForm } from "./_components/OnboardingForm";

export default async function OnboardingPage() {
  const supabase = await createSupabaseServerClient();

  // Get current user
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    throw new Error("Expected authenticated user in onboarding page; middleware should handle redirects.");
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
