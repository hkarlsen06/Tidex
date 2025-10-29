import type { Metadata } from 'next';
import { connection } from "next/server";
import { verifySession } from '@/data-access/auth';
import { getUserProfile } from '@/data-access/settings';
import { ProfileForm } from '@components/settings/profile/ProfileForm';
import { PhoneConnectionCard } from '@components/settings/profile/PhoneConnectionCard';
import { PasswordCard } from '@components/settings/profile/PasswordCard';
import { GoogleConnectionCard } from '@components/settings/profile/GoogleConnectionCard';
import { DangerZone } from '@components/settings/profile/DangerZone';
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
    title: t.pages.settings.profile.title,
  };
}

export default async function ProfilePage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  await connection();
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  // Verify authentication and get user
  const { user } = await verifySession();

  const profile = await getUserProfile(user.id);

  return (
    <div className="container mx-auto py-8 max-w-2xl">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.profile.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.profile.subtitle}
          </p>
        </div>

        <ProfileForm initialData={profile} />

        <PasswordCard hasPassword={profile.hasPassword} />

        {/* Account connections */}
        <div className="space-y-4 pt-4">
          <div className="border-t border-border pt-4">
            <h3 className="text-lg font-semibold text-text-primary mb-1">
              {t.pages.settings.profile.connectionsTitle}
            </h3>
            <p className="text-sm text-text-secondary mb-4">
              {t.pages.settings.profile.connectionsSubtitle}
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

        {/* Danger zone at the very bottom */}
        <div className="pt-4">
          <DangerZone />
        </div>
      </div>
    </div>
  );
}
