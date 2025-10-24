import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import { HomeContent } from "../../components/app/HomeContent";

export default async function Home() {
  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect("/login");
  }

  // Redirect to onboarding if user hasn't finished onboarding
  const finishedOnboarding = user.user_metadata?.finishedOnboarding ?? false;
  if (!finishedOnboarding) {
    redirect("/onboarding");
  }

  const { shifts, settings } = await getComputedShifts(user.id);

  return <HomeContent shifts={shifts} settings={settings} />;
}
