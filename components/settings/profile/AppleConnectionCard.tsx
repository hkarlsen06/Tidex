'use client';

import { useState } from 'react';
import Image from 'next/image';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { useRouter } from 'next/navigation';
import { connectAppleAccount, disconnectAppleAccount } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { useTranslations } from '@/lib/i18n/client';

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
      // Build redirect URL dynamically based on current origin
      const redirectUrl = `${window.location.origin}/auth/callback`;

      // Use server action to get the OAuth URL
      const { url } = await connectAppleAccount(redirectUrl);

      // Navigate to Apple OAuth
      window.location.href = url;
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
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
            <Image src="/icons/apple.svg" alt="Apple" width={24} height={24} className="dark:invert" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="font-semibold text-text-primary">{t.pages.settings.profile.apple.title}</h3>
            <p className="text-sm text-text-secondary mt-0.5">
              {hasAppleConnected
                ? t.pages.settings.profile.apple.connected
                : t.pages.settings.profile.apple.notConnected}
            </p>
            {error && (
              <p className="text-sm text-destructive mt-2">
                {error}
              </p>
            )}
          </div>
        </div>
        <div className="w-full sm:w-auto sm:shrink-0 flex flex-col gap-2 sm:items-end">
          <Button
            variant={hasAppleConnected ? 'outline' : 'default'}
            onClick={hasAppleConnected ? handleDisconnect : handleConnect}
            disabled={isLoading || (hasAppleConnected && !canDisconnectApple)}
            title={
              hasAppleConnected && !canDisconnectApple
                ? t.pages.settings.profile.apple.addOtherMethod
                : undefined
            }
            className="w-full sm:w-auto"
          >
            {isLoading
              ? t.pages.settings.profile.apple.processing
              : hasAppleConnected
              ? t.pages.settings.profile.apple.disconnect
              : t.pages.settings.profile.apple.connect}
          </Button>
          {hasAppleConnected && !canDisconnectApple && (
            <p className="text-xs text-text-secondary text-left sm:text-right">
              {t.pages.settings.profile.apple.addOtherMethod}
            </p>
          )}
        </div>
      </div>
    </Card>
  );
}
