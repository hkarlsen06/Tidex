import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { getUserSettings } from '../_data/getSettings';
import { DisplayForm } from '@components/settings/display/DisplayForm';
import { BackButton } from '@appui/BackButton';

export default async function DisplayPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  const settings = await getUserSettings(user.id);

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <BackButton label="Innstillinger" fallbackHref="/settings" />

      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">Utseende</h2>
          <p className="text-text-secondary mt-1">
            Tilpass hvordan appen ser ut
          </p>
        </div>

        <DisplayForm
          initialData={{
            theme: settings.theme || 'system',
            defaultShiftsView: settings.default_shifts_view || 'list',
          }}
        />
      </div>
    </div>
  );
}
