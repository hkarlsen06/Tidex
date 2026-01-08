'use client';

import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Separator } from '@/components/app/Separator';
import { Tabs, TabsList, TabsTrigger } from '@/components/app/Tabs';
import { Check, RefreshCw, ExternalLink } from 'lucide-react';
import { cn } from '@/lib/utils';

type BillingPeriod = 'monthly' | 'yearly';
import { useState, useEffect, useCallback } from 'react';
import { usePathname, useRouter } from 'next/navigation';
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
  isPopular?: boolean;
  onUpgrade: () => void;
  isLoading?: boolean;
  billingPeriod: BillingPeriod;
  showSavingsBadge?: boolean;
  t: Dictionary;
  disabled?: boolean;
  /** Show skeleton for price and name while StoreKit data loads */
  storeKitLoading?: boolean;
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
  storeKitLoading,
}: PlanCardProps) {
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
          {/* Name and description from StoreKit - show skeleton while loading */}
          {storeKitLoading ? (
            <div className="h-8 w-24 bg-surface-secondary rounded animate-pulse" />
          ) : (
            <h3 className="text-2xl font-bold">{name}</h3>
          )}
          {storeKitLoading ? (
            <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse mt-1" />
          ) : (
            <p className="text-sm text-text-secondary mt-1">{description}</p>
          )}
        </div>

        <div className="space-y-2">
          <div className="flex items-baseline gap-1">
            {storeKitLoading ? (
              <div className="h-10 w-32 bg-surface-secondary rounded animate-pulse" />
            ) : (
              <span className="text-4xl font-bold">{price}</span>
            )}
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
  const [errorKey, setErrorKey] = useState<string | null>(null);
  const [billingPeriod, setBillingPeriod] = useState<BillingPeriod>('monthly');

  const router = useRouter();
  const pathname = usePathname();
  // Extract locale from pathname (e.g., /no/settings/subscription -> 'no')
  const locale = pathname?.split('/')[1] || 'no';

  // Access IAP translations
  const iap = t.pages.settings.subscription.upgradePlans.iap;

  // Retry counter to trigger re-initialization
  const [retryCount, setRetryCount] = useState(0);

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

      // Reset state for retry
      setError(null);
      setErrorKey(null);
      setProducts([]);
      setIsInitialized(false);
      setIsInitializing(true);
      currentStep = 'starting';

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
        const productsResult = await getProducts();

        if (isCancelled) return;

        if (productsResult.products.length === 0) {
          // Use specific error message for empty products
          console.warn("[IAP UI] No products received from getProducts():", productsResult);
          setError(productsResult.error || iap.errors.noProducts);
          setErrorKey(IAP_ERROR_KEYS.NO_PRODUCTS);
          setIsInitializing(false);
          // Don't return - allow UI to show but with error state
          // This way user can still see the restore button
        } else {
          console.log("[IAP UI] Setting products:", JSON.stringify(productsResult.products, null, 2));
          setProducts(productsResult.products);
        }

        // Step 4: Complete
        currentStep = 'complete';
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
  }, [iap, retryCount]);

  // Retry function
  const handleRetry = useCallback(() => {
    setRetryCount((c) => c + 1);
  }, []);

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
          // User explicitly cancelled - redirect to cancel page
          if (result.error === 'Purchase cancelled' || result.error === iap.purchaseCancelled) {
            router.push(`/${locale}/settings/subscription/cancel`);
            return;
          }
          // For other errors, show inline so user can retry
          const errorWithHint = result.error?.includes('Unable to Complete')
            ? `${result.error}. ${iap.tryRestoreHint || 'If you already have a subscription, try "Restore purchases" below.'}`
            : result.error || iap.purchaseFailed;
          setError(errorWithHint);
          setLoadingPlan(null);
          return;
        }

        if (result.entitled) {
          // Success! Redirect to success page (same as Stripe flow)
          if (result.restoredFromExisting) {
            // For restore, show alert then redirect
            alert(iap.subscriptionRestored || 'Your existing subscription has been restored!');
          }
          router.push(`/${locale}/settings/subscription/success`);
          return;
        } else if (result.error) {
          // Purchase succeeded but verification had issues
          setError(result.error);
        } else if (result.restoredFromExisting) {
          // Auto-restore was attempted but no entitlement found
          setError(result.error || iap.subscriptionOnDifferentAccount || 'This subscription is linked to a different account.');
        }

        setLoadingPlan(null);
      } catch (e: any) {
        setError(e.message || iap.purchaseFailed);
        setLoadingPlan(null);
      }
    },
    [appAccountToken, supabaseAccessToken, iap, router, locale]
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
        // Found active subscription, redirect to success page
        router.push(`/${locale}/settings/subscription/success`);
        return;
      } else {
        setError(iap.noActiveSubscriptions);
      }

      setIsRestoring(false);
    } catch (e: any) {
      setError(e.message || iap.restoreFailed);
      setIsRestoring(false);
    }
  }, [appAccountToken, supabaseAccessToken, iap, router, locale]);

  // Get product data from StoreKit - Apple requires using their provided title and price
  const getProduct = (productId: string) => products.find((p) => p.id === productId);

  const getProductPrice = (productId: string, fallback: string): string => {
    const product = getProduct(productId);
    console.log("[IAP UI] getProductPrice:", {
      productId,
      fallback,
      foundProduct: product,
      returningPrice: product?.price || fallback,
      allProductIds: products.map(p => p.id),
    });
    return product?.price || fallback;
  };

  // Get product title from StoreKit (Apple requires this for App Store compliance)
  const getProductTitle = (productId: string, fallback: string): string => {
    const product = getProduct(productId);
    return product?.title || fallback;
  };

  // Get product description from StoreKit (Apple requires this for App Store compliance)
  const getProductDescription = (productId: string, fallback: string): string => {
    const product = getProduct(productId);
    return product?.description || fallback;
  };

  const getProProductId = () => billingPeriod === 'monthly'
    ? APPLE_PRODUCT_IDS.PRO_MONTHLY
    : APPLE_PRODUCT_IDS.PRO_YEARLY;

  const getMaxProductId = () => billingPeriod === 'monthly'
    ? APPLE_PRODUCT_IDS.MAX_MONTHLY
    : APPLE_PRODUCT_IDS.MAX_YEARLY;

  // Use StoreKit-provided data (required by Apple for App Store compliance)
  const getProTitle = () => getProductTitle(getProProductId(), t.pages.settings.subscription.upgradePlans.proName);
  const getMaxTitle = () => getProductTitle(getMaxProductId(), t.pages.settings.subscription.upgradePlans.maxName);
  const getProDescription = () => getProductDescription(getProProductId(), t.pages.settings.subscription.upgradePlans.proDescription);
  const getMaxDescription = () => getProductDescription(getMaxProductId(), t.pages.settings.subscription.upgradePlans.maxDescription);

  const getProPrice = () => billingPeriod === 'monthly'
    ? getProductPrice(APPLE_PRODUCT_IDS.PRO_MONTHLY, '29,00 kr')
    : getProductPrice(APPLE_PRODUCT_IDS.PRO_YEARLY, '249,00 kr');

  const getMaxPrice = () => billingPeriod === 'monthly'
    ? getProductPrice(APPLE_PRODUCT_IDS.MAX_MONTHLY, '59,00 kr')
    : getProductPrice(APPLE_PRODUCT_IDS.MAX_YEARLY, '499,00 kr');

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

      {/* Error display with retry button */}
      {error && (
        <div className={cn(
          "p-4 rounded-lg text-sm",
          errorKey === IAP_ERROR_KEYS.NO_PRODUCTS
            ? "bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400"
            : "bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400"
        )}>
          <p>{error}</p>
          {errorKey === IAP_ERROR_KEYS.NO_PRODUCTS && (
            <p className="mt-2 text-xs opacity-75">
              {iap.errors.noProductsHint}
            </p>
          )}
          <Button
            variant="outline"
            size="sm"
            className="mt-3"
            onClick={handleRetry}
            disabled={isInitializing}
          >
            <RefreshCw className={cn("h-4 w-4 mr-2", isInitializing && "animate-spin")} />
            {iap.errors.retry}
          </Button>
        </div>
      )}

      {/* Show billing toggle and plan cards - with skeleton prices while loading */}
      {/* Hide only if we got the NO_PRODUCTS error (products failed to load) */}
      {errorKey !== IAP_ERROR_KEYS.NO_PRODUCTS && (
        <>
          {/* Billing period toggle */}
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
              name={getProTitle()}
              price={getProPrice()}
              description={getProDescription()}
              features={t.pages.settings.subscription.upgradePlans.proFeatures}
              isPopular={true}
              billingPeriod={billingPeriod}
              showSavingsBadge={true}
              onUpgrade={() => handleUpgrade(getProTitle(), getProProductId())}
              isLoading={loadingPlan === getProTitle()}
              disabled={shouldDisableButtons}
              storeKitLoading={products.length === 0}
              t={t}
            />

            <PlanCard
              name={getMaxTitle()}
              price={getMaxPrice()}
              description={getMaxDescription()}
              features={t.pages.settings.subscription.upgradePlans.maxFeatures}
              billingPeriod={billingPeriod}
              showSavingsBadge={true}
              onUpgrade={() => handleUpgrade(getMaxTitle(), getMaxProductId())}
              isLoading={loadingPlan === getMaxTitle()}
              disabled={shouldDisableButtons}
              storeKitLoading={products.length === 0}
              t={t}
            />
          </div>
        </>
      )}

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
