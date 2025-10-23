import { createSupabaseServerClient } from '@/lib/supabase/server';
import { DataForm } from '@components/settings/data/DataForm';

export default async function DataPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Expected authenticated user in data settings page; middleware should handle redirects.');
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <div className="mt-6">
        <DataForm />
      </div>
    </div>
  );
}
