import type { Metadata } from 'next';
import { connection } from "next/server";
import { verifySession } from '@/data-access/auth';
import { getUserSettings } from '@/data-access/settings';
import { getUserWageSnapshots, getSnapshotForDate } from '@/data-access/wage-snapshots';
import { PayForm } from '@components/settings/pay/PayForm';
import { WageHistoryList } from '@components/settings/pay/WageHistoryList';
import { CurrentWageCard } from '@components/settings/pay/CurrentWageCard';
import { ReSnapshotCard } from '@components/settings/data/ReSnapshotCard';
import { Separator } from '@appui/Separator';
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
  await connection();
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  // Verify authentication and get user
  const { user } = await verifySession();

  const settings = await getUserSettings(user.id);
  const wageSnapshots = await getUserWageSnapshots();

  // Get current wage snapshot (applicable today)
  const today = new Date().toISOString().split('T')[0];
  const currentSnapshot = await getSnapshotForDate(today);

  return (
    <div className="container mx-auto py-8 max-w-2xl">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.pay.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.pay.subtitle}
          </p>
        </div>

        <CurrentWageCard currentSnapshot={currentSnapshot} />

        <Separator />

        <WageHistoryList snapshots={wageSnapshots} />

        <Separator className="mt-6" />

        <PayForm initialData={settings} />

        <Separator className="mt-6" />

        <ReSnapshotCard t={t} />
      </div>
    </div>
  );
}
