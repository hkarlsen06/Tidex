import type { Metadata } from 'next';
import { connection } from 'next/server';
import { verifySession } from '@/data-access/auth';
import { FeedbackPage as FeedbackPageClient } from '@/components/settings/feedback/FeedbackPage';
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
    title: t.pages.settings.feedback?.title || 'Feedback',
  };
}

export default async function FeedbackPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  await connection();
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);

  // Verify authentication
  await verifySession();

  return (
    <SettingsPageWrapper routeKey="settings-feedback">
      <FeedbackPageClient t={t} />
    </SettingsPageWrapper>
  );
}
