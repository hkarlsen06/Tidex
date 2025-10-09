import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { getUserSettings } from '../_data/getSettings';
import { PayForm } from '@components/settings/pay/PayForm';

export default async function PayPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  const settings = await getUserSettings(user.id);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">L�nn og tillegg</h2>
        <p className="text-text-secondary mt-1">
          Konfigurer l�nnsinnstillinger og tillegg
        </p>
      </div>

      <PayForm initialData={settings} />
    </div>
  );
}
