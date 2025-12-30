'use client';

import { useEffect, useState } from 'react';
import {
  isNativePlatform,
  getPlatform,
  waitForCapacitorBridge,
} from '@/lib/capacitor/platform';
import { UpgradeOptions } from './UpgradeOptions';
import { AppleIAPUpgradeOptions } from './AppleIAPUpgradeOptions';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { supabase } from '@/lib/supabase/browser';

interface PlatformAwareUpgradeOptionsProps {
  t: Dictionary;
}

/**
 * Platform-aware upgrade options component.
 * - On iOS: Shows Apple IAP upgrade flow
 * - On Web/Android: Shows Stripe upgrade flow
 */
export function PlatformAwareUpgradeOptions({ t }: PlatformAwareUpgradeOptionsProps) {
  const [platform, setPlatform] = useState<'ios' | 'android' | 'web'>('web');
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isNative, setIsNative] = useState(false);

  useEffect(() => {
    async function detectPlatform() {
      // Wait for Capacitor bridge to be available (important for remote URL loading)
      await waitForCapacitorBridge(1500);

      // Detect platform after bridge is ready
      const currentPlatform = getPlatform();
      const native = isNativePlatform();

      setPlatform(currentPlatform);
      setIsNative(native);

      // Get Supabase access token for iOS IAP verification
      if (currentPlatform === 'ios' && native) {
        // Use getClaims() to validate JWT locally (faster than getUser())
        const { data, error } = await supabase.auth.getClaims();
        if (!error && data) {
          // JWT is valid, get access token from session
          const { data: { session } } = await supabase.auth.getSession();
          setAccessToken(session?.access_token ?? null);
        }
      }

      setIsLoading(false);
    }

    detectPlatform();
  }, []);

  // Show loading state while detecting platform
  if (isLoading) {
    return (
      <div className="animate-pulse space-y-4">
        <div className="h-8 bg-surface-secondary rounded w-1/3" />
        <div className="h-64 bg-surface-secondary rounded" />
      </div>
    );
  }

  // iOS: Use Apple IAP
  if (platform === 'ios' && isNative) {
    if (!accessToken) {
      return (
        <div className="text-center py-8 text-text-secondary">
          <p>{t.pages.settings.subscription.upgradePlans.sessionVerifyFailed}</p>
        </div>
      );
    }

    return <AppleIAPUpgradeOptions t={t} supabaseAccessToken={accessToken} />;
  }

  // Web and Android: Use Stripe
  return <UpgradeOptions t={t} />;
}
