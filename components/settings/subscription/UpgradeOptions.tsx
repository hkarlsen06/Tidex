'use client';

import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { Separator } from '@appui/Separator';
import { Check } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useState } from 'react';
import { createCheckoutSession } from '@/app/[locale]/(app)/settings/subscription/_actions/createCheckoutSession';
import { ENV } from '@/lib/env';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface PlanCardProps {
  name: string;
  price: string;
  description: string;
  features: readonly string[];
  isPopular?: boolean;
  onUpgrade: () => void;
  isLoading?: boolean;
  t: Dictionary;
}

function PlanCard({ name, price, description, features, isPopular, onUpgrade, isLoading, t }: PlanCardProps) {
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

        <div className="flex items-baseline gap-1">
          <span className="text-4xl font-bold">{price}</span>
          <span className="text-text-secondary">{t.pages.settings.subscription.upgradePlans.perMonth}</span>
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

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold mb-2">{t.pages.settings.subscription.upgradePlans.title}</h3>
        <p className="text-sm text-text-secondary">
          {t.pages.settings.subscription.upgradePlans.description}
        </p>
      </div>

      <div className="flex flex-col gap-6">
        <PlanCard
          name={t.pages.settings.subscription.upgradePlans.proName}
          price={t.pages.settings.subscription.upgradePlans.proPrice}
          description={t.pages.settings.subscription.upgradePlans.proDescription}
          features={t.pages.settings.subscription.upgradePlans.proFeatures}
          isPopular={true}
          onUpgrade={() => handleUpgrade('Pro', ENV.PRO_PRICE_ID!)}
          isLoading={loadingPlan === 'Pro'}
          t={t}
        />

        <PlanCard
          name={t.pages.settings.subscription.upgradePlans.maxName}
          price={t.pages.settings.subscription.upgradePlans.maxPrice}
          description={t.pages.settings.subscription.upgradePlans.maxDescription}
          features={t.pages.settings.subscription.upgradePlans.maxFeatures}
          onUpgrade={() => handleUpgrade('Max', ENV.MAX_PRICE_ID!)}
          isLoading={loadingPlan === 'Max'}
          t={t}
        />
      </div>
    </div>
  );
}
