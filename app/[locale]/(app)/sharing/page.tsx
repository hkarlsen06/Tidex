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
    manage?: string;    // Deep link: open manage sharing modal (from share_started notification)
    highlight?: string; // Deep link: highlight this user in manage modal (user ID to prompt share back)
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
  const { view, user: userParam, dates, manage, highlight } = await searchParams;

  // Support both 'view' (existing) and 'user' (deep link from push notification) params
  const selectedOwnerId = view ?? userParam;
  // Parse comma-separated dates into a Set for efficient lookup
  const highlightDates = dates ? new Set(dates.split(",")) : null;
  // Deep link: open manage modal and highlight a specific person (from share_started notification)
  const openManageModal = manage === "true";
  const highlightUserId = highlight || null;

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
          openManageModal={openManageModal}
          highlightUserId={highlightUserId}
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
  // First try to find in non-blocked sharers (normal list)
  let selectedSharer = sharers.find(s => s.id === selectedOwnerId) ?? null;

  // If not found, check if this is a blocked user we still have share access to
  // (e.g., accessing via notification deep link for a user we've hidden from our list)
  // The 'blocked' flag only hides from the list - it doesn't revoke access to their shifts
  if (!selectedSharer) {
    const friendEntry = friends.find(f => f.id === selectedOwnerId);
    // If they share with me (even if blocked), create a SharedUser-like object for display
    if (friendEntry?.sharesWithMe) {
      selectedSharer = {
        id: friendEntry.id,
        email: friendEntry.email,
        phone: friendEntry.phone,
        firstName: friendEntry.firstName,
        profilePictureUrl: friendEntry.profilePictureUrl,
        oauthAvatarUrl: friendEntry.oauthAvatarUrl,
        sharedAt: friendEntry.sharesWithMe.sharedAt,
        showEarnings: friendEntry.sharesWithMe.showEarningsToMe,
        notificationFrequency: friendEntry.sharesWithMe.notificationFrequency,
      };
    }
  }

  if (!selectedSharer) {
    // Truly invalid sharer ID - no share relationship exists
    return (
      <I18nProvider locale={_locale as Locale} dictionary={dictionary} namespaces={['pages.sharing', 'pages.shifts']}>
        <SharingDefaultView
          friends={friends}
          shareCapacity={shareCapacity}
          hasSharers={sharers.length > 0}
          openManageModal={openManageModal}
          highlightUserId={highlightUserId}
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
