'use client';

import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Separator } from '@/components/app/Separator';
import { Tabs, TabsList, TabsTrigger } from '@/components/app/Tabs';
import { Check } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useState } from 'react';
import { createCheckoutSession } from '@/app/[locale]/(app)/settings/subscription/_actions/createCheckoutSession';
import { ENV } from '@/lib/env';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

type BillingPeriod = 'monthly' | 'yearly';

interface PlanCardProps {
  name: string;
  price: string;
  description: string;
  features: readonly string[];
  isPopular?: boolean;
  onUpgrade: () => void;
  isLoading?: boolean;
  billingPeriod: BillingPeriod;
  showSavingsBadge?: boolean;
  t: Dictionary;
}

function PlanCard({ name, price, description, features, isPopular, onUpgrade, isLoading, billingPeriod, showSavingsBadge, t }: PlanCardProps) {
  const periodLabel = billingPeriod === 'monthly'
    ? t.pages.settings.subscription.upgradePlans.perMonth
    : t.pages.settings.subscription.upgradePlans.perYear;

  return (
    <Card
      className={cn(
        'p-6 relative',
        isPopular && 'border-2 border-text-primary'
      )}
    >
      {isPopular && (
        <div className="absolute -top-3 left-1/2 -translate-x-1/2">
          <span className="bg-text-primary text-background px-3 py-1 text-xs font-semibold rounded-full">
            {t.pages.settings.subscription.upgradePlans.popularBadge}
          </span>
        </div>
      )}

      <div className="space-y-6">
        <div>
          <h3 className="text-2xl font-bold">{name}</h3>
          <p className="text-sm text-text-secondary mt-1">{description}</p>
        </div>

        <div className="space-y-2">
          <div className="flex items-baseline gap-1">
            <span className="text-4xl font-bold">{price}</span>
            <span className="text-text-secondary">{periodLabel}</span>
          </div>
          {showSavingsBadge && billingPeriod === 'yearly' && (
            <div className="inline-flex items-center bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 px-2 py-1 rounded-md text-xs font-medium">
              {t.pages.settings.subscription.upgradePlans.saveBadge}
            </div>
          )}
        </div>

        <Separator />

        <ul className="space-y-3">
          {features.map((feature, index) => (
            <li key={index} className="flex gap-3 items-start">
              <Check className="h-5 w-5 text-green-600 dark:text-green-500 flex-shrink-0 mt-0.5" />
              <span className="text-sm text-text-secondary">{feature}</span>
            </li>
          ))}
        </ul>

        <Button
          onClick={onUpgrade}
          className="w-full"
          variant={isPopular ? 'default' : 'outline'}
          disabled={isLoading}
        >
          {isLoading ? t.pages.settings.subscription.upgradePlans.loading : t.pages.settings.subscription.upgradePlans.upgradeButton.replace('{plan}', name)}
        </Button>
      </div>
    </Card>
  );
}

interface UpgradeOptionsProps {
  t: Dictionary;
}

export function UpgradeOptions({ t }: UpgradeOptionsProps) {
  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [billingPeriod, setBillingPeriod] = useState<BillingPeriod>('monthly');

  const handleUpgrade = async (planName: string, priceId: string) => {
    try {
      setLoadingPlan(planName);

      const result = await createCheckoutSession(priceId);

      if (result.success && result.url) {
        // Redirect to Stripe checkout
        window.location.href = result.url;
      } else {
        alert(result.error || 'Kunne ikke opprette checkout-sesjon');
        setLoadingPlan(null);
      }
    } catch (error) {
      console.error('Error creating checkout session:', error);
      alert('En uventet feil oppstod. Vennligst prøv igjen.');
      setLoadingPlan(null);
    }
  };

  const getProPrice = () => billingPeriod === 'monthly'
    ? t.pages.settings.subscription.upgradePlans.proPrice
    : t.pages.settings.subscription.upgradePlans.proYearlyPrice;

  const getMaxPrice = () => billingPeriod === 'monthly'
    ? t.pages.settings.subscription.upgradePlans.maxPrice
    : t.pages.settings.subscription.upgradePlans.maxYearlyPrice;

  const getProPriceId = () => billingPeriod === 'monthly'
    ? ENV.PRO_PRICE_ID!
    : ENV.PRO_YEARLY_PRICE_ID!;

  const getMaxPriceId = () => billingPeriod === 'monthly'
    ? ENV.MAX_PRICE_ID!
    : ENV.MAX_YEARLY_PRICE_ID!;

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold mb-2">{t.pages.settings.subscription.upgradePlans.title}</h3>
        <p className="text-sm text-text-secondary">
          {t.pages.settings.subscription.upgradePlans.description}
        </p>
      </div>

      <div className="flex justify-center">
        <Tabs value={billingPeriod} onValueChange={(value) => setBillingPeriod(value as BillingPeriod)}>
          <TabsList>
            <TabsTrigger value="monthly">
              {t.pages.settings.subscription.upgradePlans.billingPeriodMonthly}
            </TabsTrigger>
            <TabsTrigger value="yearly">
              {t.pages.settings.subscription.upgradePlans.billingPeriodYearly}
            </TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      <div className="flex flex-col gap-6">
        <PlanCard
          name={t.pages.settings.subscription.upgradePlans.proName}
          price={getProPrice()}
          description={t.pages.settings.subscription.upgradePlans.proDescription}
          features={t.pages.settings.subscription.upgradePlans.proFeatures}
          isPopular={true}
          billingPeriod={billingPeriod}
          showSavingsBadge={true}
          onUpgrade={() => handleUpgrade('Pro', getProPriceId())}
          isLoading={loadingPlan === 'Pro'}
          t={t}
        />

        <PlanCard
          name={t.pages.settings.subscription.upgradePlans.maxName}
          price={getMaxPrice()}
          description={t.pages.settings.subscription.upgradePlans.maxDescription}
          features={t.pages.settings.subscription.upgradePlans.maxFeatures}
          billingPeriod={billingPeriod}
          showSavingsBadge={true}
          onUpgrade={() => handleUpgrade('Max', getMaxPriceId())}
          isLoading={loadingPlan === 'Max'}
          t={t}
        />
      </div>
    </div>
  );
}
