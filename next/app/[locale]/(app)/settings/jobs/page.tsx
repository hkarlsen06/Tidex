import type { Metadata } from 'next';
import { verifySession } from '@/data-access/auth';
import { getUserJobs } from '@/data-access/jobs';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';
import { SettingsPageWrapper } from '@/components/app/SettingsPageWrapper';
import { JobsSettingsClient } from '@/components/settings/jobs/JobsSettingsClient';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);
  return {
    title: t.pages.settings.jobs.title,
  };
}

export default async function JobsSettingsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);
  const { user } = await verifySession();
  const jobs = await getUserJobs(user.id, { includeArchived: true });

  return (
    <SettingsPageWrapper routeKey="settings-jobs">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.jobs.title}</h2>
          <p className="mt-1 text-text-secondary">{t.pages.settings.jobs.subtitle}</p>
        </div>
        <JobsSettingsClient jobs={jobs} />
      </div>
    </SettingsPageWrapper>
  );
}
