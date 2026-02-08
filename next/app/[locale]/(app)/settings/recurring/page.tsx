import type { Metadata } from "next";
import { verifySession } from "@/data-access/auth";
import { getUserSettings } from "@/data-access/settings";
import { PRESET_RULES } from "@/data-access/shifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getTranslations } from "@/lib/i18n/server";
import type { Locale } from "@/lib/i18n/config";
import { SettingsPageWrapper } from "@/components/app/SettingsPageWrapper";
import { RecurringShiftsSettingsList } from "@/components/settings/recurring/RecurringShiftsSettingsList";
import type { ExistingShift } from "@/lib/recurring/conflicts";
import type { RecurringShiftRow } from "@/lib/recurring/types";
import type { UserSettings } from "@/lib/payroll";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ["pages.settings"]);
  return {
    title: t.pages.settings.recurring.title,
  };
}

export default async function RecurringSettingsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ["pages.settings"]);
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const [settings, recurringResult, shiftsResult] = await Promise.all([
    getUserSettings(user.id),
    supabase
      .from("recurring_shifts")
      .select("id,user_id,start_time,end_time,repeat_interval_weeks,selected_days,end_condition,exclusions,date_specific_supplements")
      .eq("user_id", user.id)
      .is("deleted_at", null),
    supabase
      .from("user_shifts")
      .select("shift_date,start_time,end_time")
      .eq("user_id", user.id)
      .is("deleted_at", null),
  ]);

  const recurringShifts = (recurringResult.data ?? []) as RecurringShiftRow[];
  const existingShifts = (shiftsResult.data ?? []) as ExistingShift[];
  const userSettings: UserSettings = settings ?? {};

  return (
    <SettingsPageWrapper routeKey="settings-recurring">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.recurring.title}</h2>
          <p className="mt-1 text-text-secondary">
            {t.pages.settings.recurring.subtitle}
          </p>
        </div>

        <RecurringShiftsSettingsList
          recurringShifts={recurringShifts}
          existingShifts={existingShifts}
          userSettings={userSettings}
          presetRules={PRESET_RULES}
          cacheKey={user.id}
        />
      </div>
    </SettingsPageWrapper>
  );
}
