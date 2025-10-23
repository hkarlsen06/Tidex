import { createSupabaseServerClient } from '@/lib/supabase/server';
import { getUserSettings } from '../_data/getSettings';
import { PreferencesForm } from '@components/settings/preferences/PreferencesForm';

export default async function PreferencesPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Expected authenticated user in preferences settings page; middleware should handle redirects.');
  }

  const settings = await getUserSettings(user.id);

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">Preferanser</h2>
          <p className="text-text-secondary mt-1">
            Tilpass hvordan du bruker appen
          </p>
        </div>

        <PreferencesForm
          initialData={{
            directTimeInput: settings.direct_time_input ?? false,
            fullMinuteRange: settings.full_minute_range ?? false,
          }}
        />
      </div>
    </div>
  );
}
