import { Suspense } from "react";
import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getStatsData } from "./_data/getStatsData";
import { StatsContent } from "@/components/app/StatsContent";
import { StatsSkeleton } from "@/components/app/skeletons/StatsSkeleton";

export const metadata: Metadata = {
  title: "Statistikk",
};

export default async function StatsPage() {
  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect("/login");
  }

  return (
    <Suspense fallback={<StatsSkeleton />}>
      <StatsDataLoader userId={user.id} />
    </Suspense>
  );
}

async function StatsDataLoader({ userId }: { userId: string }) {
  const data = await getStatsData(userId);
  return <StatsContent data={data} />;
}
