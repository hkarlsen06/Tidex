import { connection } from "next/server";
import { verifySession } from "@/data-access/auth";
import { getUsersWhoSharedWithMe, getMyShareRecipients, canAddMoreRecipients, getSharedUserShifts } from "@/data-access/sharing";
import { getTranslations } from "@/lib/i18n/server";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { SharingPageContent } from "@/components/sharing/SharingPageContent";
import { PRESET_RULES } from "@/data-access/shifts";
import {
  getPreviousYearMonth,
  getNextYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";

interface SharingPageProps {
  params: Promise<{ locale: string }>;
  searchParams: Promise<{ view?: string }>;
}

export async function generateMetadata({ params }: SharingPageProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.sharing']);

  return {
    title: t.pages?.sharing?.title ?? "Deling",
  };
}

export default async function SharingPage({ params, searchParams }: SharingPageProps) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale: _locale } = await params;
  const { view: selectedOwnerId } = await searchParams;
  const dictionary = getAppDictionary(_locale as Locale, ['pages.sharing', 'pages.shifts']);

  // Verify authentication and get user
  const { user } = await verifySession();

  // Fetch sharing data
  const [sharers, recipients, shareCapacity] = await Promise.all([
    getUsersWhoSharedWithMe(user.id),
    getMyShareRecipients(user.id),
    canAddMoreRecipients(user.id),
  ]);

  // If viewing a specific sharer's shifts, fetch them
  let sharedShifts = null;
  let sharedSettings = null;
  let sharedAggregates = null;
  let selectedSharer = null;
  let showEarnings = true;

  if (selectedOwnerId && sharers.some(s => s.id === selectedOwnerId)) {
    selectedSharer = sharers.find(s => s.id === selectedOwnerId) ?? null;

    // Fetch 3 months of shifts for the selected sharer
    const prevMonth = getPreviousYearMonth();
    const nextMonth = getNextYearMonth();

    const sharedData = await getSharedUserShifts(selectedOwnerId, {
      startDate: getMonthStart(prevMonth.year, prevMonth.month),
      endDate: getMonthEnd(nextMonth.year, nextMonth.month),
      limit: 150
    });

    sharedShifts = sharedData.shifts;
    sharedSettings = sharedData.settings;
    sharedAggregates = sharedData.aggregates;
    showEarnings = sharedData.showEarnings;
  }

  return (
    <I18nProvider locale={_locale as Locale} dictionary={dictionary} namespaces={['pages.sharing', 'pages.shifts']}>
      <SharingPageContent
        sharers={sharers}
        recipients={recipients}
        shareCapacity={shareCapacity}
        selectedOwnerId={selectedOwnerId ?? null}
        selectedSharer={selectedSharer}
        sharedShifts={sharedShifts}
        sharedSettings={sharedSettings ?? {}}
        sharedAggregates={sharedAggregates}
        presetRules={PRESET_RULES}
        showEarnings={showEarnings}
      />
    </I18nProvider>
  );
}
