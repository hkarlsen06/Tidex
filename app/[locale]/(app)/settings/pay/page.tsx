import type { Metadata } from 'next';
import { connection } from "next/server";
import { verifySession } from '@/data-access/auth';
import { getUserSettings } from '@/data-access/settings';
import { getUserWageSnapshots } from '@/data-access/wage-snapshots';
import { PayForm } from '@components/settings/pay/PayForm';
import { WageHistoryTimeline } from '@components/settings/pay/WageHistoryTimeline';
import { Separator } from '@/components/app/Separator';
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
    title: t.pages.settings.pay.title,
  };
}

export default async function PayPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  await connection();
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);

  // Verify authentication and get user
  const { user } = await verifySession();

  const settings = await getUserSettings(user.id);
  const wageSnapshots = await getUserWageSnapshots();

  return (
    <SettingsPageWrapper routeKey="settings-pay">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.pay.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.pay.subtitle}
          </p>
        </div>

        <WageHistoryTimeline snapshots={wageSnapshots} t={t} />

        <Separator />

        <PayForm initialData={settings} />
      </div>
    </SettingsPageWrapper>
  );
}
