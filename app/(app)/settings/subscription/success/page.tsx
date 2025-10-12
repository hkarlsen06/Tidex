import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { Card } from '@appui/Card';
import { CheckCircle } from 'lucide-react';
import { SubscriptionSuccessButtons } from './SubscriptionSuccessButtons';

export default async function SubscriptionSuccessPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <Card className="p-8">
        <div className="flex flex-col items-center text-center space-y-6">
          <div className="w-16 h-16 bg-green-100 dark:bg-green-900/30 rounded-full flex items-center justify-center">
            <CheckCircle className="w-10 h-10 text-green-600 dark:text-green-500" />
          </div>

          <div className="space-y-2">
            <h1 className="text-3xl font-bold">Velkommen til Premium!</h1>
            <p className="text-text-secondary">
              Takk for at du oppgraderte. Abonnementet ditt er nå aktivt.
            </p>
          </div>

          <div className="w-full p-4 bg-surface-secondary rounded-lg text-left">
            <h3 className="font-semibold mb-2">Hva skjer nå?</h3>
            <ul className="space-y-2 text-sm text-text-secondary">
              <li>✓ Abonnementet ditt er aktivert</li>
              <li>✓ Du har nå tilgang til alle premium-funksjoner</li>
              <li>✓ En bekreftelse er sendt til e-posten din</li>
              <li>✓ Du kan administrere abonnementet ditt når som helst</li>
            </ul>
          </div>

          <SubscriptionSuccessButtons />
        </div>
      </Card>
    </div>
  );
}
