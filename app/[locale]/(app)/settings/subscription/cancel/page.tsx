import { redirect } from 'next/navigation';
import { connection } from 'next/server';
import type { Metadata } from 'next';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { Card } from '@appui/Card';
import { XCircle } from 'lucide-react';
import { SubscriptionCancelButtons } from './SubscriptionCancelButtons';

export const metadata: Metadata = {
  title: "Oppgradering avbrutt",
};

export default async function SubscriptionCancelPage() {
  await connection(); // Opt out of prerendering for dynamic authenticated pages

  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect('/login');
  }

  return (
    <div className="container mx-auto py-8 max-w-2xl">
      <Card className="p-8">
        <div className="flex flex-col items-center text-center space-y-6">
          <div className="w-16 h-16 bg-surface-secondary rounded-full flex items-center justify-center">
            <XCircle className="w-10 h-10 text-text-secondary" />
          </div>

          <div className="space-y-2">
            <h1 className="text-3xl font-bold">Oppgradering avbrutt</h1>
            <p className="text-text-secondary">
              Betalingsprosessen ble avbrutt. Ingen bekymring - du kan prøve igjen når som helst.
            </p>
          </div>

          <div className="w-full p-4 bg-surface-secondary rounded-lg text-left">
            <h3 className="font-semibold mb-2">Trenger du hjelp?</h3>
            <p className="text-sm text-text-secondary">
              Hvis du opplevde problemer eller har spørsmål om våre planer, ikke nøl med å ta kontakt med oss.
            </p>
          </div>

          <SubscriptionCancelButtons />
        </div>
      </Card>
    </div>
  );
}
