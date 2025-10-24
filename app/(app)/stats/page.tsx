import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getStatsData } from "./_data/getStatsData";
import { StatsContent } from "@/components/app/StatsContent";

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

  const data = await getStatsData(user.id);

  return <StatsContent data={data} />;
}
