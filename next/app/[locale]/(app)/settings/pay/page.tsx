import type { Metadata } from 'next';
import Link from 'next/link';
import { connection } from "next/server";
import { verifySession } from '@/data-access/auth';
import { getUserSettings } from '@/data-access/settings';
import { getUserWageSnapshots } from '@/data-access/wage-snapshots';
import { getLatestTariffVersion } from '@/data-access/tariff';
import { getUserJobs } from '@/data-access/jobs';
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
  searchParams,
}: {
  params: Promise<{ locale: string }>;
  searchParams: Promise<{ job?: string }>;
}) {
  await connection();
  const { locale } = await params;
  const { job } = await searchParams;
  const t = getTranslations(locale as Locale, ['pages.settings']);

  // Verify authentication and get user
  const { user } = await verifySession();

  const settings = await getUserSettings(user.id);
  const jobs = await getUserJobs(user.id, { includeArchived: true });
  const activeJobs = jobs.filter((entry) => !entry.deleted_at && !entry.archived_at);
  const selectedJob =
    activeJobs.find((entry) => entry.id === job) ??
    activeJobs.find((entry) => entry.is_default) ??
    activeJobs[0] ??
    null;
  const selectedJobId = selectedJob?.id ?? null;
  const wageSnapshots = await getUserWageSnapshots(selectedJobId ?? undefined);
  // Fetch latest tariff version for creating new snapshots
  const latestTariffVersion = await getLatestTariffVersion('hk_retail');

  return (
    <SettingsPageWrapper routeKey="settings-pay">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.pay.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.pay.subtitle}
          </p>
        </div>

        {activeJobs.length > 1 && (
          <div className="flex flex-wrap gap-2">
            {activeJobs.map((entry) => {
              const isActive = entry.id === selectedJobId;
              return (
                <Link
                  key={entry.id}
                  href={`/${locale}/settings/pay?job=${entry.id}`}
                  className={`rounded-full border px-3 py-1.5 text-sm transition ${
                    isActive
                      ? 'border-border bg-surface-secondary text-text-primary'
                      : 'border-border-subtle text-text-secondary hover:bg-surface-secondary/70'
                  }`}
                >
                  {entry.name}
                </Link>
              );
            })}
          </div>
        )}

        <WageHistoryTimeline
          snapshots={wageSnapshots}
          t={t}
          initialTariffVersion={latestTariffVersion}
          jobId={selectedJobId}
        />

        <Separator />

        <PayForm
          key={selectedJobId ?? 'default-job-pay-form'}
          initialData={{
            half_tax_month: selectedJob?.half_tax_month ?? settings?.half_tax_month ?? null,
            monthly_goal: selectedJob?.monthly_goal ?? settings?.monthly_goal ?? null,
            payroll_day: selectedJob?.payroll_day ?? settings?.payroll_day ?? null,
          }}
          jobId={selectedJobId}
        />
      </div>
    </SettingsPageWrapper>
  );
}
