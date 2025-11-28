import type { Metadata } from 'next';
import { verifySession } from '@/data-access/auth';
import { getUserProfile } from '@/data-access/settings';
import { PasswordCard } from '@components/settings/profile/PasswordCard';
import { PhoneConnectionCard } from '@components/settings/profile/PhoneConnectionCard';
import { GoogleConnectionCard } from '@components/settings/profile/GoogleConnectionCard';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';
import { MfaSection } from './MfaSection';
import { SettingsPageWrapper } from '@/components/app/SettingsPageWrapper';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);
  return {
    title: t.pages.settings.security.title,
  };
}

export default async function SecurityPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);

  // Verify authentication and get user
  const { user } = await verifySession();

  const profile = await getUserProfile(user.id);

  return (
    <SettingsPageWrapper routeKey="settings-security">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.security.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.security.subtitle}
          </p>
        </div>

        {/* Password section */}
        <PasswordCard hasPassword={profile.hasPassword} isPhoneOnly={profile.isPhoneOnly} />

        {/* Connected accounts section */}
        <div className="space-y-4 pt-4">
          <div className="border-t border-border pt-4">
            <h3 className="text-lg font-semibold text-text-primary mb-1">
              {t.pages.settings.security.connectionsTitle}
            </h3>
            <p className="text-sm text-text-secondary mb-4">
              {t.pages.settings.security.connectionsSubtitle}
            </p>
          </div>

          <PhoneConnectionCard
            hasPhoneConnected={profile.hasPhoneConnected}
            phoneNumber={profile.phoneNumber}
            canUnlinkPhone={profile.canUnlinkPhone}
          />

          <GoogleConnectionCard
            hasGoogleConnected={profile.hasGoogleConnected}
            canDisconnectGoogle={profile.canDisconnectGoogle}
          />
        </div>

        {/* Two-factor authentication section */}
        <div className="space-y-4 pt-4">
          <div className="border-t border-border pt-4">
            <h3 className="text-lg font-semibold text-text-primary mb-1">
              {t.pages.settings.security.mfaTitle}
            </h3>
            <p className="text-sm text-text-secondary mb-4">
              {t.pages.settings.security.mfaSubtitle}
            </p>
          </div>

          <MfaSection />
        </div>
      </div>
    </SettingsPageWrapper>
  );
}
