import { redirect } from "next/navigation";
import type { Metadata } from "next";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import {
  getPreviousYearMonth,
  getNextYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";
import { HomeContent } from "../../components/app/HomeContent";

export const metadata: Metadata = {
  title: "Hjem - KKarlsen.DEV",
};

export default async function Home() {
  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect("/login");
  }

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
