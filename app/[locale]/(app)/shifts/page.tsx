import { getComputedShifts, PRESET_RULES } from "@/data-access/shifts";
import { connection } from "next/server";
import {
  getPreviousYearMonth,
  getNextYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";
import { ShiftsView } from "@components/shifts/ShiftsView";
import { getTranslations } from "@/lib/i18n/server";
import type { Locale } from "@/lib/i18n/config";

interface ShiftsPageProps {
  params: Promise<{ locale: string }>;
}

export async function generateMetadata({ params }: ShiftsPageProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  return {
    title: t.pages.shifts.title,
  };
}

export default async function ShiftsPage({ params }: ShiftsPageProps) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale: _locale } = await params;

  // Fetch 3 months of data (previous + current + next) for smooth navigation
  // This covers 90% of user navigation patterns without loading states
  const prevMonth = getPreviousYearMonth();
  const nextMonth = getNextYearMonth();

  const { shifts, defaultView, settings } = await getComputedShifts({
    startDate: getMonthStart(prevMonth.year, prevMonth.month),
    endDate: getMonthEnd(nextMonth.year, nextMonth.month),
    limit: 150 // Accommodate up to ~50 shifts per month across 3 months
  });

  return <ShiftsView shifts={shifts} defaultView={defaultView} userSettings={settings} presetRules={PRESET_RULES} />;
}
