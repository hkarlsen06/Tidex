import { redirect } from 'next/navigation';
import type { Metadata } from 'next';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { getUserSettings } from '../_data/getSettings';
import { DisplayForm } from '@components/settings/display/DisplayForm';

export const metadata: Metadata = {
  title: "Utseende",
};

export default async function DisplayPage() {
  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect('/login');
  }

  const settings = await getUserSettings(user.id);

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
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
