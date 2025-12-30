import { Suspense } from "react";
import { connection } from "next/server";
import { verifySession } from "@/data-access/auth";
import { getUsersWhoSharedWithMe, canAddMoreRecipients, getSharedUserShifts, getAllFriends } from "@/data-access/sharing";
import { getTranslations } from "@/lib/i18n/server";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { SharingPageContent } from "@/components/sharing/SharingPageContent";
import { SharingDefaultView } from "@/components/sharing/SharingDefaultView";
import { SharersListWithPreviews } from "@/components/sharing/SharersListWithPreviews";
import { SharersListSkeleton } from "@/components/app/skeletons";
import { PRESET_RULES } from "@/data-access/shifts";
import {
  getPreviousYearMonth,
  getNextYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";

interface SharingPageProps {
  params: Promise<{ locale: string }>;
  searchParams: Promise<{
    view?: string;
    user?: string;      // Deep link: owner ID from push notification
    dates?: string;     // Deep link: comma-separated dates to highlight in calendar
  }>;
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
  const { view, user: userParam, dates } = await searchParams;

  // Support both 'view' (existing) and 'user' (deep link from push notification) params
  const selectedOwnerId = view ?? userParam;
  // Parse comma-separated dates into a Set for efficient lookup
  const highlightDates = dates ? new Set(dates.split(",")) : null;

  const dictionary = getAppDictionary(_locale as Locale, ['pages.sharing', 'pages.shifts']);

  // Verify authentication and get user
  const { user } = await verifySession();

  // Fetch sharing data in parallel
  const [sharers, friends, shareCapacity] = await Promise.all([
    getUsersWhoSharedWithMe(user.id),
    getAllFriends(user.id),
    canAddMoreRecipients(user.id),
  ]);

  // Default view: no sharer selected - use streaming for shift previews
  if (!selectedOwnerId) {
    return (
      <I18nProvider locale={_locale as Locale} dictionary={dictionary} namespaces={['pages.sharing', 'pages.shifts']}>
        <SharingDefaultView
          friends={friends}
          shareCapacity={shareCapacity}
          hasSharers={sharers.length > 0}
        >
          {sharers.length > 0 ? (
            <Suspense fallback={<SharersListSkeleton count={sharers.length} />}>
              <SharersListWithPreviews sharers={sharers} locale={_locale} />
            </Suspense>
          ) : null}
        </SharingDefaultView>
      </I18nProvider>
    );
  }

  // Detail view: viewing a specific sharer's shifts
  const selectedSharer = sharers.find(s => s.id === selectedOwnerId) ?? null;

  if (!selectedSharer) {
    // Invalid sharer ID, redirect to default view
    return (
      <I18nProvider locale={_locale as Locale} dictionary={dictionary} namespaces={['pages.sharing', 'pages.shifts']}>
        <SharingDefaultView
          friends={friends}
          shareCapacity={shareCapacity}
          hasSharers={sharers.length > 0}
        >
          {sharers.length > 0 ? (
            <Suspense fallback={<SharersListSkeleton count={sharers.length} />}>
              <SharersListWithPreviews sharers={sharers} locale={_locale} />
            </Suspense>
          ) : null}
        </SharingDefaultView>
      </I18nProvider>
    );
  }

  // Fetch 3 months of shifts for the selected sharer
  const prevMonth = getPreviousYearMonth();
  const nextMonth = getNextYearMonth();

  const sharedData = await getSharedUserShifts(selectedOwnerId, {
    startDate: getMonthStart(prevMonth.year, prevMonth.month),
    endDate: getMonthEnd(nextMonth.year, nextMonth.month),
    limit: 150
  });

  return (
    <I18nProvider locale={_locale as Locale} dictionary={dictionary} namespaces={['pages.sharing', 'pages.shifts']}>
      <SharingPageContent
        sharers={sharers}
        friends={friends}
        shareCapacity={shareCapacity}
        selectedOwnerId={selectedOwnerId}
        selectedSharer={selectedSharer}
        sharedShifts={sharedData.shifts}
        sharedSettings={sharedData.settings ?? {}}
        sharedAggregates={sharedData.aggregates}
        presetRules={PRESET_RULES}
        showEarnings={sharedData.showEarnings}
        highlightDates={highlightDates}
      />
    </I18nProvider>
  );
}
