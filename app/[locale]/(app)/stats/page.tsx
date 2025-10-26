import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getStatsData } from "./_data/getStatsData";
import { StatsContent } from "@/components/app/StatsContent";
import { getTranslations } from "@/lib/i18n/server";
import type { Locale } from "@/lib/i18n/config";

interface StatsPageProps {
  params: Promise<{ locale: string }>;
}

export async function generateMetadata({ params }: StatsPageProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  return {
    title: t.pages.stats.title,
  };
}

export default async function StatsPage({ params }: StatsPageProps) {
  const { locale } = await params;
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
  const data = await getStatsData(user.id, { locale: locale as Locale });
  return <StatsContent data={data} />;
}
