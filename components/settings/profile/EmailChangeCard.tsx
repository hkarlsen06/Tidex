'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Label } from '@appui/Label';
import { IconMail, IconCheck } from '@tabler/icons-react';
import {
  initiateEmailChange,
} from '@/app/(app)/settings/_actions/updateSettings';
import { translateError } from '@/lib/errors/translate';

interface EmailChangeCardProps {
  currentEmail: string;
  onCancel: () => void;
  onComplete: () => void;
}

type ChangeStep = 'input' | 'sent';

export function EmailChangeCard({ currentEmail, onCancel }: EmailChangeCardProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [changeStep, setChangeStep] = useState<ChangeStep>('input');
  const [newEmailInput, setNewEmailInput] = useState('');

  const handleInitiateChange = async () => {
    // Basic validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(newEmailInput)) {
      setError('Ugyldig e-postadresse.');
      return;
    }

    if (newEmailInput === currentEmail) {
      setError('Den nye e-postadressen må være forskjellig fra den nåværende.');
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      await initiateEmailChange(newEmailInput);
      setChangeStep('sent');
    } catch (err) {
      console.error('Failed to initiate email change:', err);
      setError(
        err instanceof Error
          ? translateError(err.message)
          : 'En feil oppstod'
      );
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Card className="p-6">
      <div className="space-y-4">
        <div className="flex items-center gap-4">
          <div className="p-3 rounded-lg bg-surface-secondary flex-shrink-0">
            <IconMail className="h-6 w-6 text-text-primary" />
          </div>
          <div className="flex-1">
            <h3 className="font-semibold text-text-primary">
              Endre e-postadresse
            </h3>
            <p className="text-sm text-text-secondary mt-0.5">
              {changeStep === 'input'
                ? 'Skriv inn din nye e-postadresse'
                : 'Sjekk din e-post for bekreftelseslenker'}
            </p>
          </div>
        </div>

        {changeStep === 'input' ? (
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="current-email">Nåværende e-postadresse</Label>
              <Input
                id="current-email"
                type="email"
                value={currentEmail}
                disabled
                className="opacity-60"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="new-email">Ny e-postadresse</Label>
              <Input
                id="new-email"
                type="email"
                placeholder="ny@epost.no"
                value={newEmailInput}
                onChange={(e) => {
                  setNewEmailInput(e.target.value);
                  setError(null);
                }}
                disabled={isLoading}
              />
            </div>

            {error && <p className="text-sm text-destructive">{error}</p>}

            <div className="flex gap-2">
              <Button
                onClick={handleInitiateChange}
                disabled={isLoading || !newEmailInput}
                className="flex-1"
              >
                {isLoading ? 'Sender...' : 'Send bekreftelse'}
              </Button>
              <Button
                variant="outline"
                onClick={onCancel}
                disabled={isLoading}
              >
                Avbryt
              </Button>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex flex-col items-center justify-center py-6">
              <div className="mb-4 p-4 rounded-full bg-green-100 dark:bg-green-900/30">
                <IconCheck className="h-8 w-8 text-green-600 dark:text-green-400" />
              </div>
              <h4 className="text-lg font-semibold text-text-primary mb-2">
                Bekreftelse sendt!
              </h4>
              <p className="text-sm text-text-secondary text-center max-w-md">
                Vi har sendt bekreftelseslenker til både <strong>{currentEmail}</strong> og <strong>{newEmailInput}</strong>.
                Du må klikke på begge lenkene for å fullføre endringen.
              </p>
              <p className="text-sm text-text-secondary text-center mt-3">
                Har du ikke tilgang til den gamle e-posten?{' '}
                <a
                  href="mailto:hjalmar@kkarlsen.dev?subject=Hjelp med endring av e-postadresse"
                  className="text-brand-primary underline hover:no-underline font-medium"
                >
                  Ta kontakt
                </a>
              </p>
            </div>

            <div className="flex gap-2">
              <Button
                onClick={onCancel}
                className="flex-1"
              >
                Lukk
              </Button>
            </div>
          </div>
        )}
      </div>
    </Card>
  );
}
