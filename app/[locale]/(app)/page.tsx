import { redirect } from "next/navigation";
import { connection } from "next/server";

import { verifySession } from "@/data-access/auth";
import { getComputedShifts } from "@/data-access/shifts";
import {
  getPreviousYearMonth,
  getNextYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";
import { HomeContent } from "@/components/app/HomeContent";
import { getTranslations } from "@/lib/i18n/server";
import type { Locale } from "@/lib/i18n/config";

interface HomeProps {
  params: Promise<{ locale: string }>;
}

export async function generateMetadata({ params }: HomeProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  return {
    title: t.pages.home.title,
  };
}

export default async function Home({ params }: HomeProps) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale: _locale } = await params;

  // Verify authentication and get user
  const { user } = await verifySession();

  // Redirect to onboarding if user hasn't finished onboarding
  const finishedOnboarding = user.user_metadata?.finishedOnboarding ?? false;
  if (!finishedOnboarding) {
    redirect("/onboarding");
  }

  // Fetch 3 months of data (previous + current + next) for smooth navigation
  // This covers 90% of user navigation patterns without loading states
  const prevMonth = getPreviousYearMonth();
  const nextMonth = getNextYearMonth();

  const { shifts, settings } = await getComputedShifts(user.id, {
    startDate: getMonthStart(prevMonth.year, prevMonth.month),
    endDate: getMonthEnd(nextMonth.year, nextMonth.month),
    limit: 150 // Accommodate up to ~50 shifts per month across 3 months
  });

  return <HomeContent shifts={shifts} settings={settings} />;
}
