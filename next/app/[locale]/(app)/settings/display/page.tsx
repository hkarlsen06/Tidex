import type { Metadata } from 'next';
import { verifySession } from '@/data-access/auth';
import { getUserSettings } from '@/data-access/settings';
import { DisplayForm } from '@components/settings/display/DisplayForm';
import { CurrencySelector } from '@components/settings/display/CurrencySelector';
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
    title: t.pages.settings.display.title,
  };
}

export default async function DisplayPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {

  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);

  // Verify authentication and get user
  const { user } = await verifySession();

  const settings = await getUserSettings(user.id);

  return (
    <SettingsPageWrapper routeKey="settings-display">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.display.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.display.subtitle}
          </p>
        </div>

        <DisplayForm
          initialData={{
            theme: settings?.theme || 'system',
            defaultShiftsView: settings?.default_shifts_view || 'list',
          }}
          t={t}
        />

        <CurrencySelector
          initialCurrency={settings?.currency || 'kr'}
          t={t}
        />
      </div>
    </SettingsPageWrapper>
  );
}
