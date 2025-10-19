import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import { HomeContent } from "../../components/app/HomeContent";

export default async function Home() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    throw new Error("Expected authenticated user on home page; middleware should handle redirects.");
  }

  // Redirect to onboarding if user hasn't finished onboarding
  const finishedOnboarding = user.user_metadata?.finishedOnboarding ?? false;
  if (!finishedOnboarding) {
    redirect("/onboarding");
  }

  const { shifts, settings, aggregates } = await getComputedShifts(user.id);

  return <HomeContent shifts={shifts} settings={settings} />;
}
