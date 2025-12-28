'use client';

import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Separator } from '@/components/app/Separator';
import { Tabs, TabsList, TabsTrigger } from '@/components/app/Tabs';
import { Check, RefreshCw, ExternalLink } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useState, useEffect, useCallback } from 'react';
import {
  isIAPAvailable,
  initializeIAP,
  getProducts,
  purchaseProduct,
  restorePurchases,
  openSubscriptionManagement,
  APPLE_PRODUCT_IDS,
  type IAPProduct,
} from '@/lib/capacitor/iap';
import { getAppAccountToken } from '@/app/[locale]/(app)/settings/subscription/_actions/getAppAccountToken';
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
  disabled?: boolean;
}

function PlanCard({
  name,
  price,
  description,
  features,
  isPopular,
  onUpgrade,
  isLoading,
  billingPeriod,
  showSavingsBadge,
  t,
  disabled,
}: PlanCardProps) {
  const periodLabel =
    billingPeriod === 'monthly'
      ? t.pages.settings.subscription.upgradePlans.perMonth
      : t.pages.settings.subscription.upgradePlans.perYear;

  return (
    <Card
      className={cn('p-6 relative', isPopular && 'border-2 border-text-primary')}
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
              <Check className="h-5 w-5 text-green-600 dark:text-green-500 shrink-0 mt-0.5" />
              <span className="text-sm text-text-secondary">{feature}</span>
            </li>
          ))}
        </ul>

        <Button
          onClick={onUpgrade}
          className="w-full"
          variant={isPopular ? 'default' : 'outline'}
          disabled={isLoading || disabled}
        >
          {isLoading
            ? t.pages.settings.subscription.upgradePlans.loading
            : t.pages.settings.subscription.upgradePlans.upgradeButton.replace(
                '{plan}',
                name
              )}
        </Button>
      </div>
    </Card>
  );
}

interface AppleIAPUpgradeOptionsProps {
  t: Dictionary;
  supabaseAccessToken: string;
}

export function AppleIAPUpgradeOptions({
  t,
  supabaseAccessToken,
}: AppleIAPUpgradeOptionsProps) {
  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [billingPeriod, setBillingPeriod] = useState<BillingPeriod>('monthly');
  const [products, setProducts] = useState<IAPProduct[]>([]);
  const [isInitialized, setIsInitialized] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isRestoring, setIsRestoring] = useState(false);
  const [appAccountToken, setAppAccountToken] = useState<string | null>(null);

  // Initialize IAP and fetch products
  useEffect(() => {
    async function init() {
      if (!isIAPAvailable()) {
        setError('In-App Purchases are not available on this device');
        return;
      }

      try {
        // Get app account token
        const tokenResult = await getAppAccountToken();
        if ('error' in tokenResult) {
          setError(tokenResult.error);
          return;
        }
        setAppAccountToken(tokenResult.token);

        // Initialize IAP
        const initialized = await initializeIAP();
        if (!initialized) {
          setError('Failed to initialize In-App Purchases');
          return;
        }

        // Fetch products
        const fetchedProducts = await getProducts();
        if (fetchedProducts.length === 0) {
          setError('No products available');
          return;
        }

        setProducts(fetchedProducts);
        setIsInitialized(true);
      } catch (e: any) {
        console.error('[AppleIAPUpgradeOptions] Init error:', e);
        setError(e.message || 'Failed to load products');
      }
    }

    init();
  }, []);

  const handleUpgrade = useCallback(
    async (planName: string, productId: string) => {
      if (!appAccountToken) {
        setError('Unable to link purchase to your account');
        return;
      }

      try {
        setLoadingPlan(planName);
        setError(null);

        const result = await purchaseProduct(
          productId,
          appAccountToken,
          supabaseAccessToken
        );

        if (!result.success) {
          if (result.error !== 'Purchase cancelled') {
            setError(result.error || 'Purchase failed');
          }
          setLoadingPlan(null);
          return;
        }

        if (result.entitled) {
          // Success! Refresh the page to show new entitlement
          window.location.reload();
        } else if (result.error) {
          // Purchase succeeded but verification had issues
          setError(result.error);
        }

        setLoadingPlan(null);
      } catch (e: any) {
        console.error('[AppleIAPUpgradeOptions] Purchase error:', e);
        setError(e.message || 'Purchase failed');
        setLoadingPlan(null);
      }
    },
    [appAccountToken, supabaseAccessToken]
  );

  const handleRestore = useCallback(async () => {
    if (!appAccountToken) {
      setError('Unable to link purchases to your account');
      return;
    }

    try {
      setIsRestoring(true);
      setError(null);

      const result = await restorePurchases(
        appAccountToken,
        supabaseAccessToken
      );

      if (!result.success) {
        setError(result.error || 'Restore failed');
        setIsRestoring(false);
        return;
      }

      if (result.entitled) {
        // Found active subscription, refresh page
        window.location.reload();
      } else {
        setError('No active subscriptions found to restore');
      }

      setIsRestoring(false);
    } catch (e: any) {
      console.error('[AppleIAPUpgradeOptions] Restore error:', e);
      setError(e.message || 'Restore failed');
      setIsRestoring(false);
    }
  }, [appAccountToken, supabaseAccessToken]);

  const getProductPrice = (productId: string): string => {
    const product = products.find((p) => p.id === productId);
    return product?.price || '...';
  };

  const getProProductId = () =>
    billingPeriod === 'monthly'
      ? APPLE_PRODUCT_IDS.PRO_MONTHLY
      : APPLE_PRODUCT_IDS.PRO_YEARLY;

  // For now, only show Pro plan (Max can be added later)
  // const getMaxProductId = () =>
  //   billingPeriod === 'monthly'
  //     ? APPLE_PRODUCT_IDS.STORAGE_PLUS_MONTHLY
  //     : APPLE_PRODUCT_IDS.STORAGE_PLUS_YEARLY;

  if (!isIAPAvailable()) {
    return (
      <div className="text-center py-8 text-text-secondary">
        <p>In-App Purchases are not available on this device.</p>
        <p className="mt-2 text-sm">
          Please use the web version at app.tidex.no to manage your subscription.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold mb-2">
          {t.pages.settings.subscription.upgradePlans.title}
        </h3>
        <p className="text-sm text-text-secondary">
          {t.pages.settings.subscription.upgradePlans.description}
        </p>
      </div>

      {error && (
        <div className="p-4 bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400 rounded-lg text-sm">
          {error}
        </div>
      )}

      <div className="flex justify-center">
        <Tabs
          value={billingPeriod}
          onValueChange={(value) => setBillingPeriod(value as BillingPeriod)}
        >
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
          price={
            isInitialized
              ? getProductPrice(getProProductId())
              : t.pages.settings.subscription.upgradePlans.proPrice
          }
          description={t.pages.settings.subscription.upgradePlans.proDescription}
          features={t.pages.settings.subscription.upgradePlans.proFeatures}
          isPopular={true}
          billingPeriod={billingPeriod}
          showSavingsBadge={true}
          onUpgrade={() => handleUpgrade('Pro', getProProductId())}
          isLoading={loadingPlan === 'Pro'}
          disabled={!isInitialized}
          t={t}
        />
      </div>

      {/* Restore Purchases */}
      <div className="pt-4 border-t border-border">
        <Button
          variant="ghost"
          className="w-full justify-center gap-2"
          onClick={handleRestore}
          disabled={isRestoring || !isInitialized}
        >
          <RefreshCw
            className={cn('h-4 w-4', isRestoring && 'animate-spin')}
          />
          {isRestoring ? 'Gjenoppretter...' : 'Gjenopprett kjøp'}
        </Button>
      </div>

      {/* Manage Subscription */}
      <div className="text-center">
        <Button
          variant="link"
          className="text-sm gap-1"
          onClick={() => openSubscriptionManagement()}
        >
          Administrer abonnement
          <ExternalLink className="h-3 w-3" />
        </Button>
      </div>

      {/* Legal text for App Store */}
      <div className="text-xs text-text-muted text-center space-y-2">
        <p>
          Abonnementet fornyes automatisk med mindre det sies opp minst 24 timer
          før utløpet av inneværende periode.
        </p>
        <p>
          Betaling belastes din Apple ID-konto ved bekreftelse av kjøp.
        </p>
      </div>
    </div>
  );
}
