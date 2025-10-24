import { Suspense } from "react";
import { redirect } from "next/navigation";
import type { Metadata } from "next";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import { HomeContent } from "../../components/app/HomeContent";
import { HomeSkeleton } from "../../components/app/skeletons/HomeSkeleton";

export const metadata: Metadata = {
  title: "Hjem - KKarlsen.DEV",
};

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

  return (
    <Suspense fallback={<HomeSkeleton />}>
      <HomeDataLoader userId={user.id} />
    </Suspense>
  );
}

async function HomeDataLoader({ userId }: { userId: string }) {
  const { shifts, settings } = await getComputedShifts(userId);
  return <HomeContent shifts={shifts} settings={settings} />;
}
