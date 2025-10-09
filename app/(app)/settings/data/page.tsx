import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { DataForm } from '@components/settings/data/DataForm';
import { BackButton } from '@appui/BackButton';

export default async function DataPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <BackButton fallbackHref="/settings" />

      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">Data</h2>
          <p className="text-text-secondary mt-1">
            Eksporter eller importer dine data
          </p>
        </div>

        <DataForm />
      </div>
    </div>
  );
}
