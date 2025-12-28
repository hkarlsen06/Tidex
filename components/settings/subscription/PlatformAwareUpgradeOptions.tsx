'use client';

import { useEffect, useState } from 'react';
import { isNativePlatform, getPlatform } from '@/lib/capacitor/platform';
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

  useEffect(() => {
    // Detect platform
    const currentPlatform = getPlatform();
    setPlatform(currentPlatform);

    // Get Supabase access token for iOS IAP verification
    if (currentPlatform === 'ios') {
      supabase.auth.getSession().then(({ data }) => {
        setAccessToken(data.session?.access_token ?? null);
        setIsLoading(false);
      });
    } else {
      setIsLoading(false);
    }
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
  if (platform === 'ios' && isNativePlatform()) {
    if (!accessToken) {
      return (
        <div className="text-center py-8 text-text-secondary">
          <p>Unable to verify your session. Please try logging in again.</p>
        </div>
      );
    }

    return <AppleIAPUpgradeOptions t={t} supabaseAccessToken={accessToken} />;
  }

  // Web and Android: Use Stripe
  return <UpgradeOptions t={t} />;
}
