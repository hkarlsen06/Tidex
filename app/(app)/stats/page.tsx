import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getStatsData } from "./_data/getStatsData";
import { StatsContent } from "@/components/app/StatsContent";

export default async function StatsPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    throw new Error("Expected authenticated user in stats page; middleware should handle redirects.");
  }

  const data = await getStatsData(user.id);

  return <StatsContent data={data} />;
}
