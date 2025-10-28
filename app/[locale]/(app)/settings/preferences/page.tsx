import type { Metadata } from 'next';
import { connection } from "next/server";
import { getUserSettings } from '@/data-access/settings';
import { PreferencesForm } from '@components/settings/preferences/PreferencesForm';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);
  return {
    title: t.pages.settings.preferences.title,
  };
}

export default async function PreferencesPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  const settings = await getUserSettings();

  return (
    <div className="container mx-auto py-8 max-w-2xl">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.preferences.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.preferences.subtitle}
          </p>
        </div>

        <PreferencesForm
          initialData={{
            directTimeInput: settings.direct_time_input ?? false,
            fullMinuteRange: settings.full_minute_range ?? false,
          }}
          t={t}
        />
      </div>
    </div>
  );
}
