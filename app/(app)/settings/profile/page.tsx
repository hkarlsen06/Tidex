import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { getUserProfile } from '../_data/getSettings';
import { ProfileForm } from '@components/settings/profile/ProfileForm';
import { PhoneConnectionCard } from '@components/settings/profile/PhoneConnectionCard';
import { PasswordCard } from '@components/settings/profile/PasswordCard';
import { GoogleConnectionCard } from '@components/settings/profile/GoogleConnectionCard';
import { DangerZone } from '@components/settings/profile/DangerZone';
import { BackButton } from '@appui/BackButton';

export default async function ProfilePage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  const profile = await getUserProfile();

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <BackButton fallbackHref="/settings" />

      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">Profil</h2>
          <p className="text-text-secondary mt-1">
            Administrer din personlige informasjon
          </p>
        </div>

        <ProfileForm initialData={profile} />

        <PasswordCard hasPassword={profile.hasPassword} />

        {/* Account connections */}
        <div className="space-y-4 pt-4">
          <div className="border-t border-border pt-4">
            <h3 className="text-lg font-semibold text-text-primary mb-1">
              Tilkoblinger
            </h3>
            <p className="text-sm text-text-secondary mb-4">
              Administrer tilkoblede kontoer og autentiseringsmetoder
            </p>
          </div>

          <PhoneConnectionCard
            hasPhoneConnected={profile.hasPhoneConnected}
            phoneNumber={profile.phoneNumber}
          />

          <GoogleConnectionCard hasGoogleConnected={profile.hasGoogleConnected} />
        </div>

        {/* Danger zone at the very bottom */}
        <div className="pt-4">
          <DangerZone />
        </div>
      </div>
    </div>
  );
}
