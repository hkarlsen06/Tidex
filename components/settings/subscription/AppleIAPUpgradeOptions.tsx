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

// Timeout constant for IAP initialization (5 seconds)
const IAP_INIT_TIMEOUT_MS = 5000;

// Error keys for matching against translated errors
const IAP_ERROR_KEYS = {
  TIMEOUT: 'timeout',
  NO_PRODUCTS: 'noProducts',
  PLUGIN_NOT_AVAILABLE: 'pluginNotAvailable',
  INIT_FAILED: 'initFailed',
} as const;

export function AppleIAPUpgradeOptions({
  t,
  supabaseAccessToken,
}: AppleIAPUpgradeOptionsProps) {
  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [billingPeriod, setBillingPeriod] = useState<BillingPeriod>('monthly');
  const [products, setProducts] = useState<IAPProduct[]>([]);
  const [isInitialized, setIsInitialized] = useState(false);
  const [isInitializing, setIsInitializing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isRestoring, setIsRestoring] = useState(false);
  const [appAccountToken, setAppAccountToken] = useState<string | null>(null);
  const [initStep, setInitStep] = useState<string>('idle');
  const [errorKey, setErrorKey] = useState<string | null>(null);

  // Access IAP translations
  const iap = t.pages.settings.subscription.upgradePlans.iap;

  // Initialize IAP and fetch products with timeout
  useEffect(() => {
    let timeoutId: ReturnType<typeof setTimeout> | null = null;
    let isCancelled = false;
    let currentStep = 'idle';

    async function init() {
      if (!isIAPAvailable()) {
        setError(iap.notAvailable);
        return;
      }

      setIsInitializing(true);
      currentStep = 'starting';
      setInitStep('starting');

      // Set up timeout - uses local currentStep variable to track progress
      timeoutId = setTimeout(() => {
        if (!isCancelled) {
          setError(iap.errors.timeout);
          setErrorKey(IAP_ERROR_KEYS.TIMEOUT);
          setIsInitializing(false);
        }
      }, IAP_INIT_TIMEOUT_MS);

      try {
        // Step 1: Get app account token
        currentStep = 'getting_token';
        setInitStep('getting_token');
        const tokenResult = await getAppAccountToken();

        if (isCancelled) return;

        if ('error' in tokenResult) {
          setError(`Token error: ${tokenResult.error}`);
          setIsInitializing(false);
          return;
        }
        setAppAccountToken(tokenResult.token);

        // Step 2: Initialize IAP
        currentStep = 'initializing_iap';
        setInitStep('initializing_iap');
        const initResult = await initializeIAP();

        if (isCancelled) return;

        if (!initResult.success) {
          setError(initResult.error || iap.errors.initFailed);
          setErrorKey(IAP_ERROR_KEYS.INIT_FAILED);
          setIsInitializing(false);
          return;
        }

        // Step 3: Fetch products
        currentStep = 'fetching_products';
        setInitStep('fetching_products');
        const productsResult = await getProducts();

        if (isCancelled) return;

        if (productsResult.products.length === 0) {
          // Use specific error message for empty products
          setError(productsResult.error || iap.errors.noProducts);
          setErrorKey(IAP_ERROR_KEYS.NO_PRODUCTS);
          setIsInitializing(false);
          // Don't return - allow UI to show but with error state
          // This way user can still see the restore button
        } else {
          setProducts(productsResult.products);
        }

        // Step 4: Complete
        currentStep = 'complete';
        setInitStep('complete');
        setIsInitialized(true);
        setIsInitializing(false);

        // Clear timeout since we completed successfully
        if (timeoutId) {
          clearTimeout(timeoutId);
          timeoutId = null;
        }
      } catch (e: any) {
        if (isCancelled) return;

        setError(`Init failed at step "${currentStep}": ${e.message || 'Unknown error'}`);
        setIsInitializing(false);
      }
    }

    init();

    // Cleanup function
    return () => {
      isCancelled = true;
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
    };
  }, [iap]);

  const handleUpgrade = useCallback(
    async (planName: string, productId: string) => {
      if (!appAccountToken) {
        setError(iap.unableToLinkPurchase);
        setErrorKey(null);
        return;
      }

      try {
        setLoadingPlan(planName);
        setError(null);
        setErrorKey(null);

        const result = await purchaseProduct(
          productId,
          appAccountToken,
          supabaseAccessToken
        );

        if (!result.success) {
          // Check for cancel - the native error message is 'Purchase cancelled'
          if (result.error !== 'Purchase cancelled' && result.error !== iap.purchaseCancelled) {
            setError(result.error || iap.purchaseFailed);
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
        setError(e.message || iap.purchaseFailed);
        setLoadingPlan(null);
      }
    },
    [appAccountToken, supabaseAccessToken, iap]
  );

  const handleRestore = useCallback(async () => {
    if (!appAccountToken) {
      setError(iap.unableToLinkPurchases);
      setErrorKey(null);
      return;
    }

    try {
      setIsRestoring(true);
      setError(null);
      setErrorKey(null);

      const result = await restorePurchases(
        appAccountToken,
        supabaseAccessToken
      );

      if (!result.success) {
        setError(result.error || iap.restoreFailed);
        setIsRestoring(false);
        return;
      }

      if (result.entitled) {
        // Found active subscription, refresh page
        window.location.reload();
      } else {
        setError(iap.noActiveSubscriptions);
      }

      setIsRestoring(false);
    } catch (e: any) {
      setError(e.message || iap.restoreFailed);
      setIsRestoring(false);
    }
  }, [appAccountToken, supabaseAccessToken, iap]);

  const getProductPrice = (productId: string): string => {
    const product = products.find((p) => p.id === productId);
    return product?.price || '...';
  };

  const getProProductId = () =>
    billingPeriod === 'monthly'
      ? APPLE_PRODUCT_IDS.PRO_MONTHLY
      : APPLE_PRODUCT_IDS.PRO_YEARLY;

  const getMaxProductId = () =>
    billingPeriod === 'monthly'
      ? APPLE_PRODUCT_IDS.MAX_MONTHLY
      : APPLE_PRODUCT_IDS.MAX_YEARLY;

  // Determine if buttons should be disabled
  const shouldDisableButtons = !isInitialized || products.length === 0;

  if (!isIAPAvailable()) {
    return (
      <div className="text-center py-8 text-text-secondary">
        <p>{iap.notAvailable}</p>
        <p className="mt-2 text-sm">
          {iap.useWebVersion}
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

      {/* Initialization status while loading */}
      {isInitializing && (
        <div className="p-4 bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 rounded-lg text-sm">
          <div className="flex items-center gap-2">
            <RefreshCw className="h-4 w-4 animate-spin" />
            <span>
              {initStep === 'getting_token' && iap.initSteps.gettingToken}
              {initStep === 'initializing_iap' && iap.initSteps.initializingIAP}
              {initStep === 'fetching_products' && iap.initSteps.fetchingProducts}
              {initStep === 'starting' && iap.initSteps.starting}
            </span>
          </div>
        </div>
      )}

      {/* Error display with specific styling for "no products" */}
      {error && (
        <div className={cn(
          "p-4 rounded-lg text-sm",
          errorKey === IAP_ERROR_KEYS.NO_PRODUCTS
            ? "bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400"
            : "bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400"
        )}>
          {error}
          {errorKey === IAP_ERROR_KEYS.NO_PRODUCTS && (
            <p className="mt-2 text-xs opacity-75">
              {iap.errors.noProductsHint}
            </p>
          )}
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
            isInitialized && products.length > 0
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
          disabled={shouldDisableButtons}
          t={t}
        />

        <PlanCard
          name={t.pages.settings.subscription.upgradePlans.maxName}
          price={
            isInitialized && products.length > 0
              ? getProductPrice(getMaxProductId())
              : t.pages.settings.subscription.upgradePlans.maxPrice
          }
          description={t.pages.settings.subscription.upgradePlans.maxDescription}
          features={t.pages.settings.subscription.upgradePlans.maxFeatures}
          billingPeriod={billingPeriod}
          showSavingsBadge={true}
          onUpgrade={() => handleUpgrade('Max', getMaxProductId())}
          isLoading={loadingPlan === 'Max'}
          disabled={shouldDisableButtons}
          t={t}
        />
      </div>

      {/* Restore Purchases - allow even if products aren't loaded */}
      <div className="pt-4 border-t border-border">
        <Button
          variant="ghost"
          className="w-full justify-center gap-2"
          onClick={handleRestore}
          disabled={isRestoring || !isInitialized || !appAccountToken}
        >
          <RefreshCw
            className={cn('h-4 w-4', isRestoring && 'animate-spin')}
          />
          {isRestoring ? iap.restoring : iap.restorePurchases}
        </Button>
        {isInitialized && !appAccountToken && (
          <p className="text-xs text-text-muted text-center mt-2">
            {t.pages.settings.subscription.upgradePlans.sessionVerifyFailed}
          </p>
        )}
      </div>

      {/* Manage Subscription */}
      <div className="text-center">
        <Button
          variant="link"
          className="text-sm gap-1"
          onClick={() => openSubscriptionManagement()}
        >
          {iap.manageSubscription}
          <ExternalLink className="h-3 w-3" />
        </Button>
      </div>

      {/* Legal text for App Store */}
      <div className="text-xs text-text-muted text-center space-y-2">
        <p>{iap.legalAutoRenew}</p>
        <p>{iap.legalPayment}</p>
      </div>
    </div>
  );
}
