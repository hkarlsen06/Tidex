import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getStatsData } from "./_data/getStatsData";
import { StatsContent } from "@/components/app/StatsContent";

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

  // Fetch data directly - loading.tsx handles the loading state
  const data = await getStatsData(user.id);
  return <StatsContent data={data} />;
}
