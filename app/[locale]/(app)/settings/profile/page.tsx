import type { Metadata } from 'next';
import { verifySession } from '@/data-access/auth';
import { getUserProfile } from '@/data-access/settings';
import { getUserSubscriptionData } from '@/data-access/subscription';
import { getActiveProvider } from '@/lib/subscription/hasProAccess';
import { ProfileForm } from '@components/settings/profile/ProfileForm';
import { DangerZone } from '@components/settings/profile/DangerZone';
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
    title: t.pages.settings.profile.title,
  };
}

export default async function ProfilePage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);

  // Verify authentication and get user
  const { user } = await verifySession();

  const [profile, { subscription }] = await Promise.all([
    getUserProfile(user.id),
    getUserSubscriptionData(user.id),
  ]);

  const activeProvider = getActiveProvider(subscription);

  return (
    <SettingsPageWrapper routeKey="settings-profile">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.profile.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.profile.subtitle}
          </p>
        </div>

        <ProfileForm initialData={profile} />

        {/* Danger zone at the very bottom */}
        <div className="pt-4">
          <DangerZone
            activeSubscription={
              activeProvider ? { provider: activeProvider } : null
            }
          />
        </div>
      </div>
    </SettingsPageWrapper>
  );
}
