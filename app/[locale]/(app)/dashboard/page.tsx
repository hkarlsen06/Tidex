import { redirect } from "next/navigation";
import { connection } from "next/server";

import { verifySession } from "@/data-access/auth";
import { getComputedShifts } from "@/data-access/shifts";
import { getUserWageSnapshots } from "@/data-access/wage-snapshots";
import {
  getCurrentYearMonth,
  getPreviousYearMonth,
  getNextYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";
import { HomeContentWrapper } from "@/components/app/HomeContentWrapper";
import { getTranslations } from "@/lib/i18n/server";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";
import { I18nProvider } from "@/components/providers/I18nProvider";

interface DashboardProps {
  params: Promise<{ locale: string }>;
}

export async function generateMetadata({ params }: DashboardProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.home']);

  return {
    title: t.pages.home.title,
  };
}

export default async function DashboardPage({ params }: DashboardProps) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale: _locale } = await params;
  const dictionary = getAppDictionary(_locale as Locale, ['pages.home', 'pages.shifts']);

  // Verify authentication and get user
  const { user } = await verifySession();

  // Redirect to onboarding if user hasn't finished onboarding
  const finishedOnboarding = user.user_metadata?.finishedOnboarding ?? false;
  if (!finishedOnboarding) {
    redirect("/onboarding");
  }

  // Load current month + adjacent months (prev, next) in a single SSR request
  // This eliminates client-side API calls for the common 3-month navigation window
  const current = getCurrentYearMonth();
  const previous = getPreviousYearMonth();
  const next = getNextYearMonth();

  // Fetch shifts and wage snapshots in parallel
  const [shiftsData, wageSnapshots] = await Promise.all([
    getComputedShifts(user.id, {
      startDate: getMonthStart(previous.year, previous.month),
      endDate: getMonthEnd(next.year, next.month),
      limit: 200, // ~50 shifts per month × 3 months + headroom
      year: current.year,
      month: current.month,
    }),
    getUserWageSnapshots(),
  ]);

  const { shifts, settings } = shiftsData;

  // Pass which months were preloaded so HomeContent knows not to fetch them
  const preloadedMonths = [
    `${previous.year}-${String(previous.month).padStart(2, '0')}`,
    `${current.year}-${String(current.month).padStart(2, '0')}`,
    `${next.year}-${String(next.month).padStart(2, '0')}`,
  ];

  return (
    <I18nProvider locale={_locale as Locale} dictionary={dictionary} namespaces={['pages.home', 'pages.shifts']}>
      <HomeContentWrapper
        shifts={shifts}
        settings={settings}
        wageSnapshots={wageSnapshots}
        cacheKey={user.id.slice(0, 8)}
        preloadedMonths={preloadedMonths}
      />
    </I18nProvider>
  );
}
