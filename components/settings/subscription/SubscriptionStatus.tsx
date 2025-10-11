'use client';

import { Card } from '@appui/Card';
import { Badge } from '@appui/Badge';
import { Separator } from '@appui/Separator';
import { Button } from '@appui/Button';
import { ENV } from '@/lib/env';
import { Subscription } from '@/app/(app)/settings/subscription/_data/getSubscription';
import { createPortalSession } from '@/app/(app)/settings/subscription/_actions/createPortalSession';
import { useState } from 'react';

interface SubscriptionStatusProps {
  subscription: Subscription;
  isGrandfathered?: boolean;
}

function formatDate(dateString: string | null): string {
  if (!dateString) return 'N/A';

  const date = new Date(dateString);
  const day = date.getDate();
  const month = date.toLocaleDateString('nb-NO', { month: 'long' });
  const year = date.getFullYear();

  return `${day}. ${month} ${year}`;
}

function getPlanInfo(priceId: string | null): { name: string; price: string } {
  if (priceId === ENV.PRO_PRICE_ID) {
    return { name: 'Pro', price: '29,90 kr' };
  }
  if (priceId === ENV.MAX_PRICE_ID) {
    return { name: 'Max', price: '89,90 kr' };
  }
  return { name: 'Ukjent', price: 'N/A' };
}

function getStatusBadge(status: string) {
  const statusMap: Record<string, { label: string; variant: 'default' | 'destructive' | 'outline' | 'secondary' }> = {
    active: { label: 'Aktiv', variant: 'default' },
    past_due: { label: 'Forfalt', variant: 'destructive' },
    canceled: { label: 'Kansellert', variant: 'destructive' },
    incomplete: { label: 'Ufullstendig', variant: 'outline' },
    incomplete_expired: { label: 'Utløpt', variant: 'destructive' },
    trialing: { label: 'Prøveperiode', variant: 'secondary' },
    unpaid: { label: 'Ubetalt', variant: 'destructive' },
  };

  const statusInfo = statusMap[status] || { label: status, variant: 'outline' as const };

  return <Badge variant={statusInfo.variant}>{statusInfo.label}</Badge>;
}

export function SubscriptionStatus({ subscription, isGrandfathered = false }: SubscriptionStatusProps) {
  const planInfo = getPlanInfo(subscription.price_id);
  const [isLoading, setIsLoading] = useState(false);

  const handleManageSubscription = async () => {
    try {
      setIsLoading(true);
      const result = await createPortalSession();

      if (result.success && result.url) {
        window.location.href = result.url;
      } else {
        alert(result.error || 'Kunne ikke åpne kundeportalen');
        setIsLoading(false);
      }
    } catch (error) {
      console.error('Error opening customer portal:', error);
      alert('En uventet feil oppstod. Vennligst prøv igjen.');
      setIsLoading(false);
    }
  };

  return (
    <Card className="p-6">
      <div className="space-y-6">
        <div className="flex items-start justify-between">
          <div>
            <h3 className="text-lg font-semibold">
              {isGrandfathered ? 'Abonnementsstøtte' : 'Nåværende plan'}
            </h3>
            <p className="text-sm text-text-secondary mt-1">
              {isGrandfathered
                ? `Du støtter oss med ${planInfo.name}-abonnementet`
                : `Du er for øyeblikket på ${planInfo.name}-planen`}
            </p>
          </div>
          {getStatusBadge(subscription.status)}
        </div>

        <Separator />

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <p className="text-sm text-text-secondary mb-1">Plan</p>
            <p className="text-lg font-semibold">{planInfo.name}</p>
          </div>

          <div>
            <p className="text-sm text-text-secondary mb-1">Pris</p>
            <p className="text-lg font-semibold">{planInfo.price}/måned</p>
          </div>

          {subscription.current_period_end && (
            <div>
              <p className="text-sm text-text-secondary mb-1">Neste fornyelse</p>
              <p className="text-lg font-semibold">{formatDate(subscription.current_period_end)}</p>
            </div>
          )}

          {subscription.created_at && (
            <div>
              <p className="text-sm text-text-secondary mb-1">Første gang du abonnerte</p>
              <p className="text-lg font-semibold">{formatDate(subscription.created_at)}</p>
            </div>
          )}
        </div>

        {planInfo.name === 'Pro' && (
          <>
            <Separator />
            <div className="p-4 bg-surface-secondary rounded-lg">
              <h4 className="font-semibold mb-2">
                {isGrandfathered ? 'Du har tilgang til:' : 'Inkludert i planen din:'}
              </h4>
              <ul className="space-y-1 text-sm text-text-secondary">
                <li>✓ Lagre skift på tvers av måneder</li>
                <li>✓ Ubegrenset antall skift</li>
                <li>✓ Alle gratis funksjoner</li>
                {isGrandfathered && (
                  <li className="text-yellow-700 dark:text-yellow-400 font-medium">
                    ✓ Livstidstilgang (uavhengig av abonnement)
                  </li>
                )}
              </ul>
            </div>
          </>
        )}

        {planInfo.name === 'Max' && (
          <>
            <Separator />
            <div className="p-4 bg-surface-secondary rounded-lg">
              <h4 className="font-semibold mb-2">
                {isGrandfathered ? 'Du har tilgang til:' : 'Inkludert i planen din:'}
              </h4>
              <ul className="space-y-1 text-sm text-text-secondary">
                <li>✓ Alle Pro-funksjoner</li>
                <li>✓ Prioritert support</li>
                <li>✓ B2B-funksjoner (kommer snart)</li>
                <li>✓ Tidlig tilgang til nye funksjoner</li>
                {isGrandfathered && (
                  <li className="text-yellow-700 dark:text-yellow-400 font-medium">
                    ✓ Gratis Pro-tilgang for livet
                  </li>
                )}
              </ul>
            </div>
          </>
        )}

        <Separator />

        <div className="flex flex-col sm:flex-row gap-3">
          <Button
            onClick={handleManageSubscription}
            disabled={isLoading}
            className="flex-1"
          >
            {isLoading ? 'Laster...' : 'Administrer abonnement'}
          </Button>
        </div>
      </div>
    </Card>
  );
}
