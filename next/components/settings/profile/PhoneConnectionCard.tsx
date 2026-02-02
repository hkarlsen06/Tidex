'use client';

import { useState } from 'react';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Input } from '@/components/app/Input';
import { Label } from '@/components/app/Label';
import { Phone } from 'lucide-react';
import { useRouter } from 'next/navigation';
import {
  linkPhoneNumber,
  verifyAndLinkPhone,
  unlinkPhoneNumber,
} from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import {
  normalizePhoneToE164,
  isValidNorwegianPhone,
  formatPhoneForDisplay,
} from '@/lib/validation/phone';
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSeparator,
  InputOTPSlot,
} from '@/components/app/InputOTP';
import { translateError } from '@/lib/errors/translate';
import { useTranslations } from '@/lib/i18n/client';

interface PhoneConnectionCardProps {
  hasPhoneConnected: boolean;
  phoneNumber: string | null;
  canUnlinkPhone: boolean;
}

type LinkStep = 'input' | 'otp';

export function PhoneConnectionCard({
  hasPhoneConnected,
  phoneNumber,
  canUnlinkPhone,
}: PhoneConnectionCardProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showLinkForm, setShowLinkForm] = useState(false);
  const [linkStep, setLinkStep] = useState<LinkStep>('input');
  const [phoneInput, setPhoneInput] = useState('');
  const [otp, setOtp] = useState('');

  const handleLink = async () => {
    if (!isValidNorwegianPhone(phoneInput)) {
      setError(t.pages.settings.profile.phone.errors.phoneInvalid);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const phoneE164 = normalizePhoneToE164(phoneInput);
      await linkPhoneNumber(phoneE164);
      setLinkStep('otp');
    } catch (err) {
      console.error('Failed to send OTP:', err);
      setError(
        err instanceof Error
          ? translateError(err.message)
          : t.pages.settings.profile.phone.errors.genericError
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleVerifyOtp = async () => {
    if (otp.length !== 6) {
      setError(t.pages.settings.profile.phone.errors.otpIncomplete);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const phoneE164 = normalizePhoneToE164(phoneInput);
      await verifyAndLinkPhone(phoneE164, otp);
      setShowLinkForm(false);
      setLinkStep('input');
      setPhoneInput('');
      setOtp('');
      router.refresh();
    } catch (err) {
      console.error('Failed to verify OTP:', err);
      setError(
        err instanceof Error
          ? translateError(err.message)
          : t.pages.settings.profile.phone.errors.genericError
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleUnlink = async () => {
    setIsLoading(true);
    setError(null);

    try {
      await unlinkPhoneNumber();
      router.refresh();
    } catch (err) {
      console.error('Failed to unlink phone:', err);
      setError(
        err instanceof Error
          ? translateError(err.message)
          : t.pages.settings.profile.phone.errors.genericError
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleCancelLink = () => {
    setShowLinkForm(false);
    setLinkStep('input');
    setPhoneInput('');
    setOtp('');
    setError(null);
  };

  if (showLinkForm && !hasPhoneConnected) {
    return (
      <Card className="p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-4">
            <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
              <Phone className="h-6 w-6 text-text-primary" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-text-primary">
                {t.pages.settings.profile.phone.title}
              </h3>
              <p className="text-sm text-text-secondary mt-0.5">
                {linkStep === 'input'
                  ? t.pages.settings.profile.phone.instructionEnter
                  : t.pages.settings.profile.phone.instructionVerify}
              </p>
            </div>
          </div>

          {linkStep === 'input' ? (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="phone">{t.pages.settings.profile.phone.phoneLabel}</Label>
                <Input
                  id="phone"
                  type="text"
                  placeholder="12345678"
                  value={phoneInput}
                  onChange={(e) => {
                    setPhoneInput(e.target.value);
                    setError(null);
                  }}
                  disabled={isLoading}
                  maxLength={8}
                />
              </div>

              {error && <p className="text-sm text-destructive">{error}</p>}

              <div className="flex gap-2">
                <Button
                  onClick={handleLink}
                  disabled={isLoading || !phoneInput}
                  className="flex-1"
                >
                  {isLoading ? t.pages.settings.profile.phone.sending : t.pages.settings.profile.phone.sendCode}
                </Button>
                <Button
                  variant="outline"
                  onClick={handleCancelLink}
                  disabled={isLoading}
                >
                  {t.common.cancel}
                </Button>
              </div>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="flex flex-col items-center">
                <InputOTP
                  maxLength={6}
                  value={otp}
                  onChange={(value) => {
                    setOtp(value);
                    setError(null);
                  }}
                >
                  <InputOTPGroup>
                    <InputOTPSlot index={0} />
                    <InputOTPSlot index={1} />
                    <InputOTPSlot index={2} />
                  </InputOTPGroup>
                  <InputOTPSeparator />
                  <InputOTPGroup>
                    <InputOTPSlot index={3} />
                    <InputOTPSlot index={4} />
                    <InputOTPSlot index={5} />
                  </InputOTPGroup>
                </InputOTP>
              </div>

              {error && <p className="text-sm text-destructive">{error}</p>}

              <div className="flex gap-2">
                <Button
                  onClick={handleVerifyOtp}
                  disabled={isLoading || otp.length !== 6}
                  className="flex-1"
                >
                  {isLoading ? t.pages.settings.profile.phone.verifying : t.pages.settings.profile.phone.verify}
                </Button>
                <Button
                  variant="outline"
                  onClick={handleCancelLink}
                  disabled={isLoading}
                >
                  {t.common.cancel}
                </Button>
              </div>
            </div>
          )}
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="flex items-start gap-4">
        <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
          <Phone className="h-6 w-6 text-text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
            <div className="min-w-0">
              <h3 className="font-semibold text-text-primary">{t.pages.settings.profile.phone.titleConnected}</h3>
              <p className="text-sm text-text-secondary mt-0.5">
                {hasPhoneConnected
                  ? t.pages.settings.profile.phone.connectedAs.replace('{phone}', formatPhoneForDisplay(phoneNumber || ''))
                  : t.pages.settings.profile.phone.notConnected}
              </p>
              {hasPhoneConnected && !canUnlinkPhone && (
                <p className="text-xs text-text-muted mt-1">
                  {t.pages.settings.profile.phone.addOtherMethod}
                </p>
              )}
              {error && <p className="text-sm text-destructive mt-2">{error}</p>}
            </div>
            <Button
              variant={hasPhoneConnected ? 'outline' : 'default'}
              onClick={
                hasPhoneConnected ? handleUnlink : () => setShowLinkForm(true)
              }
              disabled={isLoading || (hasPhoneConnected && !canUnlinkPhone)}
              className="w-full sm:w-auto shrink-0"
            >
              {isLoading
                ? t.pages.settings.profile.phone.processing
                : hasPhoneConnected
                  ? t.pages.settings.profile.phone.disconnect
                  : t.pages.settings.profile.phone.connect}
            </Button>
          </div>
        </div>
      </div>
    </Card>
  );
}
