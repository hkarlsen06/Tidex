import { verifySession } from "@/data-access/auth";
import { getUserSettings } from "@/data-access/settings";
import { connection } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import AddShiftForm from "@/components/shifts/add/AddShiftForm";
import { PRESET_RULES } from "@/data-access/shifts";
import type { UserSettings } from "@/lib/payroll";
import { getTranslations } from "@/lib/i18n/server";
import type { Locale } from "@/lib/i18n/config";

interface AddShiftsPageProps {
  params: Promise<{ locale: string }>;
}

export async function generateMetadata({ params }: AddShiftsPageProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  return {
    title: t.pages.shifts.add.title,
  };
}

export default async function AddShiftsPage({ params }: AddShiftsPageProps) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale: _locale } = await params;

  // Verify authentication and get user
  const { user } = await verifySession();

  // Load user settings via DAL
  const userSettings: UserSettings = (await getUserSettings()) ?? {};

  const supabase = await createSupabaseServerClient();

  // Load only the minimal data needed to highlight conflicts in the calendar
  // Avoids the heavier getComputedShifts() call which computes payroll for every shift
  const { data: rows, error } = await supabase
    .from("user_shifts")
    .select("shift_date,start_time,end_time")
    .eq("user_id", user.id)
    .order("shift_date", { ascending: false });

  if (error) {
    // In case of an error, fall back to an empty list so the page still loads quickly
    console.error("Failed to load existing shifts for add page:", error);
  }

  const existingShifts = (rows ?? []).map((s) => ({
    shift_date: s.shift_date as string,
    start_time: s.start_time as string,
    end_time: s.end_time as string,
  }));

  return (
    <AddShiftForm
      existingShifts={existingShifts}
      userSettings={userSettings}
      presetRules={PRESET_RULES}
    />
  );
}
