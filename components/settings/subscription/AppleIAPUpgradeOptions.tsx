'use client';

import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Separator } from '@/components/app/Separator';
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

interface PlanCardProps {
  name: string;
  price: string;
  description: string;
  features: readonly string[];
  onUpgrade: () => void;
  isLoading?: boolean;
  t: Dictionary;
  disabled?: boolean;
}

function PlanCard({
  name,
  price,
  description,
  features,
  onUpgrade,
  isLoading,
  t,
  disabled,
}: PlanCardProps) {
  return (
    <Card className="p-6">
      <div className="space-y-6">
        <div>
          <h3 className="text-2xl font-bold">{name}</h3>
          <p className="text-sm text-text-secondary mt-1">{description}</p>
        </div>

        <div>
          <div className="flex items-baseline gap-1">
            <span className="text-4xl font-bold">{price}</span>
            <span className="text-text-secondary">
              {t.pages.settings.subscription.upgradePlans.perMonth}
            </span>
          </div>
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

// Timeout constant for IAP initialization (15 seconds)
// iOS StoreKit initialization + product fetch can take 5-10s on cold starts
const IAP_INIT_TIMEOUT_MS = 15000;

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
    return product?.price || '29,00 kr';
  };

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

      <PlanCard
        name={t.pages.settings.subscription.upgradePlans.proName}
        price={
          isInitialized && products.length > 0
            ? getProductPrice(APPLE_PRODUCT_IDS.PRO_MONTHLY)
            : '29,00 kr'
        }
        description={t.pages.settings.subscription.upgradePlans.proDescription}
        features={t.pages.settings.subscription.upgradePlans.proFeatures}
        onUpgrade={() => handleUpgrade('Pro', APPLE_PRODUCT_IDS.PRO_MONTHLY)}
        isLoading={loadingPlan === 'Pro'}
        disabled={shouldDisableButtons}
        t={t}
      />

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
