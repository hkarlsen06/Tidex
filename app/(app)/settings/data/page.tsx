import { redirect } from 'next/navigation';
import type { Metadata } from 'next';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { DataForm } from '@components/settings/data/DataForm';

export const metadata: Metadata = {
  title: "Data",
};

export default async function DataPage() {
  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect('/login');
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <div className="mt-6">
        <DataForm />
      </div>
    </div>
  );
}
