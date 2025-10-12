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
    paused: { label: 'Pause', variant: 'outline' },
  };

  const statusInfo = statusMap[status] || { label: status, variant: 'outline' as const };

  return <Badge variant={statusInfo.variant}>{statusInfo.label}</Badge>;
}

function getStatusDescription(status: string, planName: string, isGrandfathered: boolean): string {
  if (isGrandfathered) {
    return status === 'active'
      ? `Du støtter oss med\u00A0${planName}-abonnementet`
      : `Du støttet oss tidligere med\u00A0${planName}-abonnementet`;
  }

  if (status === 'active') {
    return `Du er for øyeblikket på ${planName}-planen`;
  }

  if (status === 'canceled') {
    return `Ditt ${planName}-abonnement er kansellert`;
  }

  if (status === 'past_due') {
    return `Ditt ${planName}-abonnement har forfalt betaling`;
  }

  if (status === 'unpaid') {
    return `Ditt ${planName}-abonnement er ubetalt`;
  }

  if (status === 'incomplete' || status === 'incomplete_expired') {
    return `Ditt ${planName}-abonnement er ikke fullført`;
  }

  if (status === 'trialing') {
    return `Du er i prøveperioden for ${planName}-planen`;
  }

  return `Ditt ${planName}-abonnement har status: ${status}`;
}

export function SubscriptionStatus({ subscription, isGrandfathered = false }: SubscriptionStatusProps) {
  const planInfo = getPlanInfo(subscription.price_id);
  const [isLoading, setIsLoading] = useState(false);
  const isActive = subscription.status === 'active';

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
              {isGrandfathered ? 'Abonnementsstøtte' : isActive ? 'Nåværende plan' : 'Tidligere abonnement'}
            </h3>
            <p className="text-sm text-text-secondary mt-1">
              {getStatusDescription(subscription.status, planInfo.name, isGrandfathered)}
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
              <p className="text-sm text-text-secondary mb-1">
                {isActive ? 'Neste fornyelse' : 'Utløper'}
              </p>
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

        {planInfo.name === 'Pro' && (isActive || isGrandfathered) && (
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

        {planInfo.name === 'Max' && (isActive || isGrandfathered) && (
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
