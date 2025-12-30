import type { Metadata } from 'next';
import { connection } from "next/server";
import { verifySession } from '@/data-access/auth';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { NotificationSettingsForm } from '@/components/settings/notifications/NotificationSettingsForm';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';
import { SettingsPageWrapper } from '@/components/app/SettingsPageWrapper';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);
  return {
    title: t.pages.settings.notifications.title,
  };
}

export default async function NotificationsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  await connection();
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);

  // Verify authentication and get user
  const { user } = await verifySession();

  // Fetch notification preferences
  const supabase = await createSupabaseServerClient();
  const { data: preferences } = await supabase
    .from('notification_preferences')
    .select('shared_shifts_enabled')
    .eq('user_id', user.id)
    .maybeSingle();

  return (
    <SettingsPageWrapper routeKey="settings-notifications">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.notifications.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.notifications.subtitle}
          </p>
        </div>

        <NotificationSettingsForm
          initialData={{
            sharedShiftsEnabled: preferences?.shared_shifts_enabled ?? true,
          }}
          t={t}
        />
      </div>
    </SettingsPageWrapper>
  );
}
