import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import Link from 'next/link';
import { XCircle } from 'lucide-react';

export default async function SubscriptionCancelPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
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

          <div className="flex gap-4 w-full">
            <Button asChild className="flex-1">
              <Link href="/settings/subscription">Prøv igjen</Link>
            </Button>
            <Button asChild variant="outline" className="flex-1">
              <Link href="/home">Gå til Dashboard</Link>
            </Button>
          </div>
        </div>
      </Card>
    </div>
  );
}
