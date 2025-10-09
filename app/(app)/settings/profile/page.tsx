import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { getUserProfile } from '../_data/getSettings';
import { ProfileForm } from '@components/settings/profile/ProfileForm';

export default async function ProfilePage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  const profile = await getUserProfile();

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">Profil</h2>
        <p className="text-text-secondary mt-1">
          Administrer din personlige informasjon
        </p>
      </div>

      <ProfileForm initialData={profile} />
    </div>
  );
}
