import { getComputedShifts, PRESET_RULES } from "@/data-access/shifts";
import { verifySession } from "@/data-access/auth";
import { connection } from "next/server";
import {
  getPreviousYearMonth,
  getNextYearMonth,
  getCurrentYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";
import { ShiftsView } from "@components/shifts/ShiftsView";
import { getTranslations } from "@/lib/i18n/server";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";
import { I18nProvider } from "@/components/providers/I18nProvider";

interface ShiftsPageProps {
  params: Promise<{ locale: string }>;
}

export async function generateMetadata({ params }: ShiftsPageProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.shifts']);

  return {
    title: t.pages.shifts.title,
  };
}

export default async function ShiftsPage({ params }: ShiftsPageProps) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale: _locale } = await params;
  const dictionary = getAppDictionary(_locale as Locale, ['pages.shifts']);

  // Verify authentication and get user
  const { user } = await verifySession();

  // Fetch 3 months of data (previous + current + next) for smooth navigation
  // This covers 90% of user navigation patterns without loading states
  const prevMonth = getPreviousYearMonth();
  const nextMonth = getNextYearMonth();
  const current = getCurrentYearMonth();

  const { shifts, defaultView, settings, payoutTaxSettings } = await getComputedShifts(user.id, {
    startDate: getMonthStart(prevMonth.year, prevMonth.month),
    endDate: getMonthEnd(nextMonth.year, nextMonth.month),
    limit: 150, // Accommodate up to ~50 shifts per month across 3 months
    year: current.year,
    month: current.month,
  });

  return (
    <I18nProvider locale={_locale as Locale} dictionary={dictionary} namespaces={['pages.shifts']}>
      <ShiftsView shifts={shifts} defaultView={defaultView} userSettings={settings} presetRules={PRESET_RULES} payoutTaxSettings={payoutTaxSettings} />
    </I18nProvider>
  );
}
