'use client';

import { useState } from 'react';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Input } from '@/components/app/Input';
import { Label } from '@/components/app/Label';
import { Mail, Check } from 'lucide-react';
import {
  initiateEmailChange,
} from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { translateError } from '@/lib/errors/translate';
import { useTranslations } from '@/lib/i18n/client';

interface EmailChangeCardProps {
  currentEmail: string;
  onCancel: () => void;
  onComplete: () => void;
}

type ChangeStep = 'input' | 'sent';

export function EmailChangeCard({ currentEmail, onCancel }: EmailChangeCardProps) {
  const { t } = useTranslations();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [changeStep, setChangeStep] = useState<ChangeStep>('input');
  const [newEmailInput, setNewEmailInput] = useState('');

  const handleInitiateChange = async () => {
    // Basic validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(newEmailInput)) {
      setError(t.pages.settings.profile.emailChange.errors.emailInvalid);
      return;
    }

    if (newEmailInput === currentEmail) {
      setError(t.pages.settings.profile.emailChange.errors.emailSameAsCurrent);
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
          : t.pages.settings.profile.emailChange.errors.genericError
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
            <Mail className="h-6 w-6 text-text-primary" />
          </div>
          <div className="flex-1">
            <h3 className="font-semibold text-text-primary">
              {t.pages.settings.profile.emailChange.title}
            </h3>
            <p className="text-sm text-text-secondary mt-0.5">
              {changeStep === 'input'
                ? t.pages.settings.profile.emailChange.instructionEnter
                : t.pages.settings.profile.emailChange.instructionCheckEmail}
            </p>
          </div>
        </div>

        {changeStep === 'input' ? (
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="current-email">{t.pages.settings.profile.emailChange.currentEmailLabel}</Label>
              <Input
                id="current-email"
                type="email"
                value={currentEmail}
                disabled
                className="opacity-60"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="new-email">{t.pages.settings.profile.emailChange.newEmailLabel}</Label>
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
                {isLoading ? t.pages.settings.profile.emailChange.sending : t.pages.settings.profile.emailChange.sendConfirmation}
              </Button>
              <Button
                variant="outline"
                onClick={onCancel}
                disabled={isLoading}
              >
                {t.common.cancel}
              </Button>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex flex-col items-center justify-center py-6">
              <div className="mb-4 p-4 rounded-full bg-green-100 dark:bg-green-900/30">
                <Check className="h-8 w-8 text-green-600 dark:text-green-400" />
              </div>
              <h4 className="text-lg font-semibold text-text-primary mb-2">
                {t.pages.settings.profile.emailChange.confirmationSent}
              </h4>
              <p className="text-sm text-text-secondary text-center max-w-md">
                {t.pages.settings.profile.emailChange.confirmationMessage
                  .replace('{oldEmail}', currentEmail)
                  .replace('{newEmail}', newEmailInput)}
              </p>
              <p className="text-sm text-text-secondary text-center mt-3">
                {t.pages.settings.profile.emailChange.contactSupport}{' '}
                <a
                  href={`mailto:${t.pages.settings.profile.emailChange.supportEmail}?subject=Hjelp med endring av e-postadresse`}
                  className="text-brand-primary underline hover:no-underline font-medium"
                >
                  {t.pages.settings.profile.emailChange.supportEmail}
                </a>
              </p>
            </div>

            <div className="flex gap-2">
              <Button
                onClick={onCancel}
                className="flex-1"
              >
                {t.common.close}
              </Button>
            </div>
          </div>
        )}
      </div>
    </Card>
  );
}
