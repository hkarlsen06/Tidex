'use client';

import { useState } from 'react';
import Image from 'next/image';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { useRouter } from 'next/navigation';
import { connectGoogleAccount, disconnectGoogleAccount } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { useTranslations } from '@/lib/i18n/client';

interface GoogleConnectionCardProps {
  hasGoogleConnected: boolean;
  canDisconnectGoogle: boolean;
}

export function GoogleConnectionCard({ hasGoogleConnected, canDisconnectGoogle }: GoogleConnectionCardProps) {
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
      const { url } = await connectGoogleAccount(redirectUrl);

      // Navigate to Google OAuth
      window.location.href = url;
    } catch (err) {
      console.error('Failed to connect Google:', err);
      setError(err instanceof Error ? err.message : t.pages.settings.profile.google.errors.genericError);
      setIsLoading(false);
    }
  };

  const handleDisconnect = async () => {
    setIsLoading(true);
    setError(null);

    try {
      // Use server action which has proper auth context
      await disconnectGoogleAccount();
      // Success! The page will refresh and show updated state
      router.refresh();
    } catch (err) {
      console.error('Failed to disconnect Google:', err);
      setError(err instanceof Error ? err.message : t.pages.settings.profile.google.errors.genericError);
    } finally {
      // Always reset loading state
      setIsLoading(false);
    }
  };

  return (
    <Card className="p-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="p-3 rounded-lg bg-surface-secondary flex-shrink-0">
            <Image src="/icons/google.svg" alt="Google" width={24} height={24} />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="font-semibold text-text-primary">{t.pages.settings.profile.google.title}</h3>
            <p className="text-sm text-text-secondary mt-0.5">
              {hasGoogleConnected
                ? t.pages.settings.profile.google.connected
                : t.pages.settings.profile.google.notConnected}
            </p>
            {error && (
              <p className="text-sm text-destructive mt-2">
                {error}
              </p>
            )}
          </div>
        </div>
        <div className="w-full sm:w-auto sm:flex-shrink-0 flex flex-col gap-2 sm:items-end">
          <Button
            variant={hasGoogleConnected ? 'outline' : 'default'}
            onClick={hasGoogleConnected ? handleDisconnect : handleConnect}
            disabled={isLoading || (hasGoogleConnected && !canDisconnectGoogle)}
            title={
              hasGoogleConnected && !canDisconnectGoogle
                ? t.pages.settings.profile.google.addOtherMethod
                : undefined
            }
            className="w-full sm:w-auto"
          >
            {isLoading
              ? t.pages.settings.profile.google.processing
              : hasGoogleConnected
              ? t.pages.settings.profile.google.disconnect
              : t.pages.settings.profile.google.connect}
          </Button>
          {hasGoogleConnected && !canDisconnectGoogle && (
            <p className="text-xs text-text-secondary text-left sm:text-right">
              {t.pages.settings.profile.google.addOtherMethod}
            </p>
          )}
        </div>
      </div>
    </Card>
  );
}
