import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { getComputedShifts, PRESET_RULES } from "./_data/getShifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  getPreviousYearMonth,
  getNextYearMonth,
  getMonthStart,
  getMonthEnd
} from "@/lib/date-utils";
import { ShiftsView } from "@components//shifts/ShiftsView";

export const metadata: Metadata = {
  title: "Vakter",
};

export default async function ShiftsPage() {
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
