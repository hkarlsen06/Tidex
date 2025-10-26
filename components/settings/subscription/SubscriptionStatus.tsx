'use client';

import { Card } from '@appui/Card';
import { Badge } from '@appui/Badge';
import { Separator } from '@appui/Separator';
import { Button } from '@appui/Button';
import { ENV } from '@/lib/env';
import { Subscription } from '@/app/[locale]/(app)/settings/subscription/_data/getSubscription';
import { createPortalSession } from '@/app/[locale]/(app)/settings/subscription/_actions/createPortalSession';
import { useState } from 'react';
import { useTranslations } from '@/lib/i18n/client';

const LEGACY_PRO_PRICE_IDS = ['price_1RzQ85Qiotkj8G58AO6st4fh'];
const LEGACY_MAX_PRICE_IDS = ['price_1RzQC1Qiotkj8G58tYo4U5oO'];

interface SubscriptionStatusProps {
  subscription: Subscription;
  isGrandfathered?: boolean;
}

function formatDate(dateString: string | null, naText: string): string {
  if (!dateString) return naText;

  const date = new Date(dateString);
  const day = date.getDate();
  const month = date.toLocaleDateString('nb-NO', { month: 'long' });
  const year = date.getFullYear();

  return `${day}. ${month} ${year}`;
}

function getPlanInfo(priceId: string | null, t: any): { name: string; price: string } {
  const tokens = t.pages.settings.subscription.status;

  if (priceId) {
    if (priceId === ENV.PRO_PRICE_ID) {
      return { name: t.pages.settings.subscription.upgradePlans.proName, price: tokens.proPriceNew };
    }
    if (LEGACY_PRO_PRICE_IDS.includes(priceId)) {
      return { name: t.pages.settings.subscription.upgradePlans.proName, price: tokens.proPriceLegacy };
    }
  }
  if (priceId && (priceId === ENV.MAX_PRICE_ID || LEGACY_MAX_PRICE_IDS.includes(priceId))) {
    return { name: t.pages.settings.subscription.upgradePlans.maxName, price: tokens.maxPrice };
  }
  return { name: tokens.planUnknown, price: tokens.priceNA };
}

function getStatusBadge(status: string, t: any) {
  const tokens = t.pages.settings.subscription.status;

  const statusMap: Record<string, { label: string; variant: 'default' | 'destructive' | 'outline' | 'secondary' }> = {
    active: { label: tokens.statusActive, variant: 'default' },
    past_due: { label: tokens.statusPastDue, variant: 'destructive' },
    canceled: { label: tokens.statusCanceled, variant: 'destructive' },
    incomplete: { label: tokens.statusIncomplete, variant: 'outline' },
    incomplete_expired: { label: tokens.statusExpired, variant: 'destructive' },
    trialing: { label: tokens.statusTrialing, variant: 'secondary' },
    unpaid: { label: tokens.statusUnpaid, variant: 'destructive' },
    paused: { label: tokens.statusPaused, variant: 'outline' },
  };

  const statusInfo = statusMap[status] || { label: status, variant: 'outline' as const };

  return <Badge variant={statusInfo.variant}>{statusInfo.label}</Badge>;
}

function getStatusDescription(
  status: string,
  planName: string,
  isGrandfathered: boolean,
  cancelAtPeriodEnd: boolean,
  t: any
): string {
  const tokens = t.pages.settings.subscription.status;

  if (isGrandfathered) {
    return status === 'active'
      ? tokens.descriptionActiveGrandfathered.replace('{plan}', planName)
      : tokens.descriptionCanceledGrandfathered.replace('{plan}', planName);
  }

  if (status === 'active') {
    if (cancelAtPeriodEnd) {
      return tokens.descriptionCanceling.replace('{plan}', planName);
    }
    return tokens.descriptionActive.replace('{plan}', planName);
  }

  if (status === 'canceled') {
    return tokens.descriptionCanceled.replace('{plan}', planName);
  }

  if (status === 'past_due') {
    return tokens.descriptionPastDue.replace('{plan}', planName);
  }

  if (status === 'unpaid') {
    return tokens.descriptionUnpaid.replace('{plan}', planName);
  }

  if (status === 'incomplete' || status === 'incomplete_expired') {
    return tokens.descriptionIncomplete.replace('{plan}', planName);
  }

  if (status === 'trialing') {
    return tokens.descriptionTrialing.replace('{plan}', planName);
  }

  return `${planName}: ${status}`;
}

export function SubscriptionStatus({ subscription, isGrandfathered = false }: SubscriptionStatusProps) {
  const { t } = useTranslations();
  const tokens = t.pages.settings.subscription.status;
  const planInfo = getPlanInfo(subscription.price_id, t);
  const [isLoading, setIsLoading] = useState(false);
  const isActive = subscription.status === 'active';
  const willBeCancelled = isActive && subscription.cancel_at_period_end;

  const handleManageSubscription = async () => {
    try {
      setIsLoading(true);
      const result = await createPortalSession();

      if (result.success && result.url) {
        window.location.href = result.url;
      } else {
        alert(result.error || tokens.errorPortal);
        setIsLoading(false);
      }
    } catch (error) {
      console.error('Error opening customer portal:', error);
      alert(tokens.errorUnexpected);
      setIsLoading(false);
    }
  };

  return (
    <Card className="p-6">
      <div className="space-y-6">
        <div className="flex items-start justify-between">
          <div>
            <h3 className="text-lg font-semibold">
              {isGrandfathered ? tokens.titleActive : isActive ? tokens.titleCurrent : tokens.titlePrevious}
            </h3>
            <p className="text-sm text-text-secondary mt-1">
              {getStatusDescription(subscription.status, planInfo.name, isGrandfathered, subscription.cancel_at_period_end, t)}
            </p>
          </div>
          {willBeCancelled ? (
            <Badge variant="outline" className="border-yellow-500 text-yellow-700 dark:text-yellow-400">
              {tokens.statusCanceling}
            </Badge>
          ) : (
            getStatusBadge(subscription.status, t)
          )}
        </div>

        <Separator />

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <p className="text-sm text-text-secondary mb-1">{tokens.planLabel}</p>
            <p className="text-lg font-semibold">{planInfo.name}</p>
          </div>

          <div>
            <p className="text-sm text-text-secondary mb-1">{tokens.priceLabel}</p>
            <p className="text-lg font-semibold">{planInfo.price}{tokens.pricePerMonth}</p>
          </div>

          {(subscription.current_period_end || subscription.cancel_at || subscription.canceled_at) && (
            <div>
              <p className="text-sm text-text-secondary mb-1">
                {subscription.status === 'canceled'
                  ? tokens.canceled
                  : subscription.cancel_at_period_end
                  ? tokens.cancels
                  : isActive
                  ? tokens.nextRenewal
                  : tokens.expires}
              </p>
              <p className="text-lg font-semibold" suppressHydrationWarning>
                {formatDate(
                  subscription.status === 'canceled'
                    ? subscription.canceled_at
                    : subscription.cancel_at_period_end
                    ? (subscription.cancel_at || subscription.current_period_end)
                    : subscription.current_period_end,
                  tokens.priceNA
                )}
              </p>
            </div>
          )}

          {(subscription.canceled_at || subscription.created_at) && (
            <div>
              <p className="text-sm text-text-secondary mb-1">
                {subscription.canceled_at ? tokens.canceledAt : tokens.firstSubscribed}
              </p>
              <p className="text-lg font-semibold" suppressHydrationWarning>
                {formatDate(subscription.canceled_at || subscription.created_at, tokens.priceNA)}
              </p>
            </div>
          )}
        </div>

        {planInfo.name === t.pages.settings.subscription.upgradePlans.proName && (isActive || isGrandfathered) && (
          <>
            <Separator />
            <div className="p-4 bg-surface-secondary rounded-lg">
              <h4 className="font-semibold mb-2">
                {isGrandfathered ? tokens.featuresIncluded : tokens.featuresIncludedPlan}
              </h4>
              <ul className="space-y-1 text-sm text-text-secondary">
                <li>✓ {tokens.proFeature1}</li>
                <li>✓ {tokens.proFeature2}</li>
                <li>✓ {tokens.proFeature3}</li>
                {isGrandfathered && (
                  <li className="text-yellow-700 dark:text-yellow-400 font-medium">
                    ✓ {tokens.lifetimeAccess}
                  </li>
                )}
              </ul>
            </div>
          </>
        )}

        {planInfo.name === t.pages.settings.subscription.upgradePlans.maxName && (isActive || isGrandfathered) && (
          <>
            <Separator />
            <div className="p-4 bg-surface-secondary rounded-lg">
              <h4 className="font-semibold mb-2">
                {isGrandfathered ? tokens.featuresIncluded : tokens.featuresIncludedPlan}
              </h4>
              <ul className="space-y-1 text-sm text-text-secondary">
                <li>✓ {tokens.maxFeature1}</li>
                <li>✓ {tokens.maxFeature2}</li>
                <li>✓ {tokens.maxFeature3}</li>
                <li>✓ {tokens.maxFeature4}</li>
                {isGrandfathered && (
                  <li className="text-yellow-700 dark:text-yellow-400 font-medium">
                    ✓ {tokens.freeProAccess}
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
            {isLoading ? tokens.loading : tokens.manageSubscription}
          </Button>
        </div>
      </div>
    </Card>
  );
}
