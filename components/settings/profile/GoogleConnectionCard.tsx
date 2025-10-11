'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { IconBrandGoogleFilled } from '@tabler/icons-react';
import { useRouter } from 'next/navigation';
import { connectGoogleAccount, disconnectGoogleAccount } from '@/app/(app)/settings/_actions/updateSettings';

interface GoogleConnectionCardProps {
  hasGoogleConnected: boolean;
}

export function GoogleConnectionCard({ hasGoogleConnected }: GoogleConnectionCardProps) {
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
      setError(err instanceof Error ? err.message : 'En feil oppstod');
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
      setError(err instanceof Error ? err.message : 'En feil oppstod');
    } finally {
      // Always reset loading state
      setIsLoading(false);
    }
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between gap-6">
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="p-3 rounded-lg bg-surface-secondary flex-shrink-0">
            <IconBrandGoogleFilled className="h-6 w-6 text-text-primary" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="font-semibold text-text-primary">Google-konto</h3>
            <p className="text-sm text-text-secondary mt-0.5">
              {hasGoogleConnected
                ? 'Du har koblet til en Google-konto for raskere pålogging'
                : 'Koble til Google-kontoen din for enklere pålogging'}
            </p>
            {error && (
              <p className="text-sm text-destructive mt-2">
                {error}
              </p>
            )}
          </div>
        </div>
        <Button
          variant={hasGoogleConnected ? 'outline' : 'default'}
          onClick={hasGoogleConnected ? handleDisconnect : handleConnect}
          disabled={isLoading}
          className="flex-shrink-0"
        >
          {isLoading
            ? 'Behandler...'
            : hasGoogleConnected
            ? 'Koble fra'
            : 'Koble til'}
        </Button>
      </div>
    </Card>
  );
}
