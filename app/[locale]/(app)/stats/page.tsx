import { getStatsData } from "@/data-access/stats";
import { verifySession } from "@/data-access/auth";
import { connection } from "next/server";
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
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale } = await params;

  // Verify authentication and get user
  const { user } = await verifySession();

  // Fetch data directly - loading.tsx handles the loading state
  const data = await getStatsData(user.id, { locale: locale as Locale });
  return <StatsContent data={data} />;
}
