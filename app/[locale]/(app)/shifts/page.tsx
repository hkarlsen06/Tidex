import { redirect } from "next/navigation";
import { getComputedShifts, PRESET_RULES } from "./_data/getShifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  getPreviousYearMonth,
  getNextYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";
import { ShiftsView } from "@components//shifts/ShiftsView";
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
  const { locale: _locale } = await params;
  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect("/login");
  }

  // Fetch 3 months of data (previous + current + next) for smooth navigation
  // This covers 90% of user navigation patterns without loading states
  const prevMonth = getPreviousYearMonth();
  const nextMonth = getNextYearMonth();

  const { shifts, defaultView, settings } = await getComputedShifts(user.id, {
    startDate: getMonthStart(prevMonth.year, prevMonth.month),
    endDate: getMonthEnd(nextMonth.year, nextMonth.month),
    limit: 150 // Accommodate up to ~50 shifts per month across 3 months
  });

  return <ShiftsView shifts={shifts} defaultView={defaultView} userSettings={settings} presetRules={PRESET_RULES} />;
}
