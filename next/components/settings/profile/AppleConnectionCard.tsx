'use client';

import { useState } from 'react';
import Image from 'next/image';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { useRouter } from 'next/navigation';
import { disconnectAppleAccount } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { useTranslations } from '@/lib/i18n/client';
import { performIdentityLink } from '@/lib/auth/oauth';
import { supabase } from '@/lib/supabase/browser';

interface AppleConnectionCardProps {
  hasAppleConnected: boolean;
  canDisconnectApple: boolean;
}

export function AppleConnectionCard({ hasAppleConnected, canDisconnectApple }: AppleConnectionCardProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleConnect = async () => {
    setIsLoading(true);
    setError(null);

    try {
      const result = await performIdentityLink(supabase, 'apple', {
        redirectPath: window.location.pathname,
      });

      if (!result.success) {
        throw result.error || new Error('Failed to initiate Apple linking');
      }

      if (result.authUrl) {
        window.location.href = result.authUrl;
      }
    } catch (err) {
      console.error('Failed to connect Apple:', err);
      setError(err instanceof Error ? err.message : t.pages.settings.profile.apple.errors.genericError);
      setIsLoading(false);
    }
  };

  const handleDisconnect = async () => {
    setIsLoading(true);
    setError(null);

    try {
      // Use server action which has proper auth context
      await disconnectAppleAccount();
      // Success! The page will refresh and show updated state
      router.refresh();
    } catch (err) {
      console.error('Failed to disconnect Apple:', err);
      setError(err instanceof Error ? err.message : t.pages.settings.profile.apple.errors.genericError);
    } finally {
      // Always reset loading state
      setIsLoading(false);
    }
  };

  return (
    <Card className="p-6">
      <div className="flex items-start gap-4">
        <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
          <Image src="/icons/apple.svg" alt="Apple" width={24} height={24} className="dark:invert" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
            <div className="min-w-0">
              <h3 className="font-semibold text-text-primary">{t.pages.settings.profile.apple.title}</h3>
              <p className="text-sm text-text-secondary mt-0.5">
                {hasAppleConnected
                  ? t.pages.settings.profile.apple.connected
                  : t.pages.settings.profile.apple.notConnected}
              </p>
              {hasAppleConnected && !canDisconnectApple && (
                <p className="text-xs text-text-muted mt-1">
                  {t.pages.settings.profile.apple.addOtherMethod}
                </p>
              )}
              {error && (
                <p className="text-sm text-destructive mt-2">
                  {error}
                </p>
              )}
            </div>
            <Button
              variant={hasAppleConnected ? 'outline' : 'default'}
              onClick={hasAppleConnected ? handleDisconnect : handleConnect}
              disabled={isLoading || (hasAppleConnected && !canDisconnectApple)}
              className="w-full sm:w-auto shrink-0"
            >
              {isLoading
                ? t.pages.settings.profile.apple.processing
                : hasAppleConnected
                ? t.pages.settings.profile.apple.disconnect
                : t.pages.settings.profile.apple.connect}
            </Button>
          </div>
        </div>
      </div>
    </Card>
  );
}
