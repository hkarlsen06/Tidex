import { verifySession } from "@/data-access/auth";
import { getUserSettings } from "@/data-access/settings";
import { connection } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { AddShiftFormWrapper } from "@/components/shifts/add/AddShiftFormWrapper";
import { PRESET_RULES } from "@/data-access/shifts";
import type { UserSettings } from "@/lib/payroll";
import { getTranslations } from "@/lib/i18n/server";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import type { Locale } from "@/lib/i18n/config";
import { generateVirtualShiftsForMonth } from "@/lib/recurring/utils";
import type { RecurringShiftRow } from "@/lib/recurring/types";
import { cleanTime } from "@/lib/time-utils";
import { logger } from "@/lib/logger";
import { getUserWageSnapshots } from "@/data-access/wage-snapshots";
import { I18nProvider } from "@/components/providers/I18nProvider";

interface AddShiftsPageProps {
  params: Promise<{ locale: string }>;
}

export async function generateMetadata({ params }: AddShiftsPageProps) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.shifts']);

  return {
    title: t.pages.shifts.add.title,
  };
}

export default async function AddShiftsPage({ params }: AddShiftsPageProps) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages
  const { locale: _locale } = await params;
  const dictionary = getAppDictionary(_locale as Locale, ['pages.shifts']);

  // Verify authentication and get user
  const { user } = await verifySession();

  // Try to load data server-side, but handle failures gracefully for offline
  let userSettings: UserSettings = {};
  let allExistingShifts: Array<{ shift_date: string; start_time: string; end_time: string }> = [];
  let wageSnapshots: any[] = [];

  try {
    // Load user settings via DAL
    userSettings = (await getUserSettings(user.id)) as UserSettings ?? {};

    const supabase = await createSupabaseServerClient();

    // Load only the minimal data needed to highlight conflicts in the calendar
    const { data: rows, error } = await supabase
      .from("user_shifts")
      .select("shift_date,start_time,end_time")
      .eq("user_id", user.id)
      .order("shift_date", { ascending: false });

    if (error) {
      console.error("Failed to load existing shifts for add page:", error);
    }

    const existingShifts = (rows ?? []).map((s) => ({
      shift_date: s.shift_date as string,
      start_time: s.start_time as string,
      end_time: s.end_time as string,
    }));

    // Load recurring shifts and generate virtual shifts for next 6 months
    const { data: recurringShifts, error: recurringError } = await supabase
      .from("recurring_shifts")
      .select("*")
      .eq("user_id", user.id);

    if (recurringError) {
      logger.error("Failed to load recurring shifts for add page:", recurringError);
    }

    const recurringVirtualShifts: Array<{ shift_date: string; start_time: string; end_time: string }> = [];
    if (recurringShifts && recurringShifts.length > 0) {
      const now = new Date();
      const currentYear = now.getFullYear();
      const currentMonth = now.getMonth() + 1;

      for (const recurring of recurringShifts as RecurringShiftRow[]) {
        for (let i = 0; i < 6; i++) {
          let targetMonth = currentMonth + i;
          let targetYear = currentYear;

          while (targetMonth > 12) {
            targetMonth -= 12;
            targetYear++;
          }

          const virtualShifts = generateVirtualShiftsForMonth(
            { year: targetYear, month: targetMonth },
            {
              start_time: cleanTime(recurring.start_time),
              end_time: cleanTime(recurring.end_time),
              repeat_interval_weeks: recurring.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8,
              selected_days: recurring.selected_days,
              end_condition: recurring.end_condition,
              exclusions: recurring.exclusions || []
            }
          );

          for (const virtualShift of virtualShifts) {
            recurringVirtualShifts.push({
              shift_date: virtualShift.date,
              start_time: cleanTime(recurring.start_time),
              end_time: cleanTime(recurring.end_time)
            });
          }
        }
      }
    }

    // Combine regular shifts and recurring virtual shifts
    allExistingShifts = [...existingShifts, ...recurringVirtualShifts];

    // Load wage snapshots for accurate preview calculations
    wageSnapshots = await getUserWageSnapshots();
  } catch (error) {
    // If server-side data loading fails (e.g., offline), return empty data
    // The wrapper component will attempt to fetch from API route
    console.error("Failed to load add shift data server-side:", error);
  }

  return (
    <I18nProvider locale={_locale as Locale} dictionary={dictionary} namespaces={['pages.shifts']}>
      <AddShiftFormWrapper
        initialData={{
          existingShifts: allExistingShifts,
          userSettings,
          presetRules: PRESET_RULES,
          wageSnapshots,
        }}
      />
    </I18nProvider>
  );
}
