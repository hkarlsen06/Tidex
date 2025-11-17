import { getStatsData } from "@/data-access/stats";
import { verifySession } from "@/data-access/auth";
import { connection } from "next/server";
import { StatsContent } from "@/components/app/StatsContent";
import { StatsLayoutWrapper } from "@/components/app/StatsLayoutWrapper";
import { getTranslations } from "@/lib/i18n/server";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";
import { I18nProvider } from "@/components/providers/I18nProvider";

interface StatsPageProps {
  params: Promise<{ locale: string }>;
}

export async function generateMetadata({ params }: StatsPageProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.stats']);

  return {
    title: t.pages.stats.title,
  };
}

export default async function StatsPage({ params }: StatsPageProps) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale } = await params;
  const dictionary = getAppDictionary(locale as Locale, ['pages.stats']);

  // Verify authentication and get user
  const { user } = await verifySession();

  // Fetch data directly - loading.tsx handles the loading state
  const data = await getStatsData(user.id, { locale: locale as Locale });
  return (
    <I18nProvider locale={locale as Locale} dictionary={dictionary} namespaces={['pages.stats']}>
      <StatsLayoutWrapper>
        <StatsContent data={data} />
      </StatsLayoutWrapper>
    </I18nProvider>
  );
}
