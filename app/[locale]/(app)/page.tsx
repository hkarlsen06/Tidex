import { redirect } from "next/navigation";
import { connection } from "next/server";

import { verifySession } from "@/data-access/auth";
import { getComputedShifts } from "@/data-access/shifts";
import {
  getCurrentYearMonth,
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

  // Performance: Load only the current month on the initial request
  // Adjacent months are fetched on the client after hydration (see HomeContent)
  // This reduces TTFB and payload size significantly, improving FCP/LCP.
  const current = getCurrentYearMonth();
  const { shifts, settings } = await getComputedShifts(user.id, {
    startDate: getMonthStart(current.year, current.month),
    endDate: getMonthEnd(current.year, current.month),
    limit: 60 // ~50 shifts is typical for a month; leave headroom
  });

  return <HomeContent shifts={shifts} settings={settings} />;
}
