'use client';

import { useState, useTransition, useEffect, useCallback } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { AlertCircle, RotateCcw, Loader2 } from 'lucide-react';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { restoreSubscription } from '@/app/[locale]/(app)/settings/subscription/_actions/restoreSubscription';
import { isNativePlatform, getPlatform, waitForCapacitorBridge } from '@/lib/capacitor/platform';
import {
  isIAPAvailable,
  initializeIAP,
  restorePurchases,
} from '@/lib/capacitor/iap';
import { getAppAccountToken } from '@/app/[locale]/(app)/settings/subscription/_actions/getAppAccountToken';
import { supabase } from '@/lib/supabase/browser';

interface FreePlanInfoProps {
  t: Dictionary;
}

export function FreePlanInfo({ t }: FreePlanInfoProps) {
  const router = useRouter();
  const pathname = usePathname();
  const locale = pathname?.split('/')[1] || 'no';

  const [isPending, startTransition] = useTransition();
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null);
  const [isIOS, setIsIOS] = useState(false);
  const [isRestoringIAP, setIsRestoringIAP] = useState(false);
  const [iapReady, setIapReady] = useState(false);

  useEffect(() => {
    async function checkPlatform() {
      await waitForCapacitorBridge(500);
      const native = isNativePlatform();
      const platform = getPlatform();
      const isiOS = native && platform === 'ios';
      setIsIOS(isiOS);

      // Initialize IAP for iOS
      if (isiOS && isIAPAvailable()) {
        const initResult = await initializeIAP();
        if (initResult.success) {
          setIapReady(true);
        }
      }
    }
    checkPlatform();
  }, []);

  // Stripe restore handler (web)
  const handleStripeRestore = () => {
    setFeedback(null);

    startTransition(async () => {
      const result = await restoreSubscription();

      if (result.success) {
        setFeedback({ type: 'success', message: t.pages.settings.subscription.freePlan.restore.success });
        router.refresh();
      } else {
        let message: string;
        switch (result.error) {
          case 'already_exists':
            // Subscription exists, just refresh to show it
            router.refresh();
            return;
          case 'not_found':
          case 'no_valid_subscription':
            message = t.pages.settings.subscription.freePlan.restore.notFound;
            break;
          default:
            message = t.pages.settings.subscription.freePlan.restore.error;
        }
        setFeedback({ type: 'error', message });
      }
    });
  };

  // Apple IAP restore handler (iOS)
  const handleIAPRestore = useCallback(async () => {
    setFeedback(null);
    setIsRestoringIAP(true);

    try {
      // Get app account token
      const tokenResult = await getAppAccountToken();
      if ('error' in tokenResult) {
        setFeedback({ type: 'error', message: t.pages.settings.subscription.freePlan.restore.error });
        setIsRestoringIAP(false);
        return;
      }

      // Get Supabase access token
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.access_token) {
        setFeedback({ type: 'error', message: t.pages.settings.subscription.freePlan.restore.error });
        setIsRestoringIAP(false);
        return;
      }

      const result = await restorePurchases(tokenResult.token, session.access_token);

      if (!result.success) {
        setFeedback({ type: 'error', message: result.error || t.pages.settings.subscription.freePlan.restore.error });
        setIsRestoringIAP(false);
        return;
      }

      if (result.entitled) {
        // Found active subscription - redirect immediately to success page
        // Use window.location for immediate navigation without re-render delay
        window.location.href = `/${locale}/settings/subscription/success`;
        return;
      } else {
        setFeedback({ type: 'error', message: t.pages.settings.subscription.freePlan.restore.notFound });
      }

      setIsRestoringIAP(false);
    } catch {
      setFeedback({ type: 'error', message: t.pages.settings.subscription.freePlan.restore.error });
      setIsRestoringIAP(false);
    }
  }, [t, locale]);

  const isLoading = isPending || isRestoringIAP;
  const isDisabled = isLoading || (isIOS && !iapReady);

  return (
    <Card className="p-6 border-border-subtle bg-surface-secondary/50">
      <div className="flex gap-3">
        <AlertCircle className="h-5 w-5 text-text-secondary shrink-0 mt-0.5" />
        <div className="flex-1">
          <h4 className="font-semibold text-sm mb-1">{t.pages.settings.subscription.freePlan.title}</h4>
          <p className="text-sm text-text-secondary">
            {t.pages.settings.subscription.freePlan.description}
          </p>

          {feedback && (
            <p
              className={`text-sm mt-3 ${
                feedback.type === 'success' ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'
              }`}
            >
              {feedback.message}
            </p>
          )}

          <Button
            variant="ghost"
            size="sm"
            onClick={isIOS ? handleIAPRestore : handleStripeRestore}
            disabled={isDisabled}
            className="mt-3 text-text-secondary hover:text-text-primary"
          >
            {isLoading ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                {t.pages.settings.subscription.freePlan.restore.loading}
              </>
            ) : (
              <>
                <RotateCcw className="h-4 w-4 mr-2" />
                {t.pages.settings.subscription.freePlan.restore.button}
              </>
            )}
          </Button>
        </div>
      </div>
    </Card>
  );
}
