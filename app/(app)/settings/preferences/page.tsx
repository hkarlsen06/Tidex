import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { getUserSettings } from '../_data/getSettings';
import { PreferencesForm } from '@components/settings/preferences/PreferencesForm';

export default async function PreferencesPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  const settings = await getUserSettings(user.id);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">Preferanser</h2>
        <p className="text-text-secondary mt-1">
          Tilpass hvordan du bruker appen
        </p>
      </div>

      <PreferencesForm
        initialData={{
          showEmployeeTab: settings.show_employee_tab ?? false,
          directTimeInput: settings.direct_time_input ?? false,
          fullMinuteRange: settings.full_minute_range ?? false,
        }}
      />
    </div>
  );
}
