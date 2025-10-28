import type { Metadata } from 'next';
import { connection } from "next/server";
import { getUserSettings } from '@/data-access/settings';
import { PayForm } from '@components/settings/pay/PayForm';
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
    title: t.pages.settings.pay.title,
  };
}

export default async function PayPage({
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
          <h2 className="text-2xl font-bold">{t.pages.settings.pay.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.pay.subtitle}
          </p>
        </div>

        <PayForm initialData={settings} />
      </div>
    </div>
  );
}
