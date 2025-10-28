import type { Metadata } from 'next';
import { connection } from "next/server";
import { getUserSettings } from '@/data-access/settings';
import { DisplayForm } from '@components/settings/display/DisplayForm';
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
    title: t.pages.settings.display.title,
  };
}

export default async function DisplayPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  await connection(); // Opt out of prerendering for dynamic authenticated pages

  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  const settings = await getUserSettings();

  return (
    <div className="container mx-auto py-8 max-w-2xl">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.display.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.display.subtitle}
          </p>
        </div>

        <DisplayForm
          initialData={{
            theme: settings.theme || 'system',
            defaultShiftsView: settings.default_shifts_view || 'list',
          }}
          t={t}
        />
      </div>
    </div>
  );
}
