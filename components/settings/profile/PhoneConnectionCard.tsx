'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Label } from '@appui/Label';
import { IconPhone } from '@tabler/icons-react';
import { useRouter } from 'next/navigation';
import {
  linkPhoneNumber,
  verifyAndLinkPhone,
  unlinkPhoneNumber,
} from '@/app/(app)/settings/_actions/updateSettings';
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
} from '@appui/InputOTP';
import { translateError } from '@/lib/errors/translate';

interface PhoneConnectionCardProps {
  hasPhoneConnected: boolean;
  phoneNumber: string | null;
}

type LinkStep = 'input' | 'otp';

export function PhoneConnectionCard({
  hasPhoneConnected,
  phoneNumber,
}: PhoneConnectionCardProps) {
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showLinkForm, setShowLinkForm] = useState(false);
  const [linkStep, setLinkStep] = useState<LinkStep>('input');
  const [phoneInput, setPhoneInput] = useState('');
  const [otp, setOtp] = useState('');

  const handleLink = async () => {
    if (!isValidNorwegianPhone(phoneInput)) {
      setError('Telefonnummer må være 8 siffer.');
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
          : 'En feil oppstod'
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleVerifyOtp = async () => {
    if (otp.length !== 6) {
      setError('Fyll inn alle 6 sifrene.');
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
          : 'En feil oppstod'
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
          : 'En feil oppstod'
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
            <div className="p-3 rounded-lg bg-surface-secondary flex-shrink-0">
              <IconPhone className="h-6 w-6 text-text-primary" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-text-primary">
                Koble til telefonnummer
              </h3>
              <p className="text-sm text-text-secondary mt-0.5">
                {linkStep === 'input'
                  ? 'Skriv inn ditt 8-sifrede telefonnummer'
                  : 'Skriv inn koden vi sendte til deg'}
              </p>
            </div>
          </div>

          {linkStep === 'input' ? (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="phone">Telefonnummer (8 siffer)</Label>
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
                  {isLoading ? 'Sender...' : 'Send kode'}
                </Button>
                <Button
                  variant="outline"
                  onClick={handleCancelLink}
                  disabled={isLoading}
                >
                  Avbryt
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
                  {isLoading ? 'Verifiserer...' : 'Verifiser'}
                </Button>
                <Button
                  variant="outline"
                  onClick={handleCancelLink}
                  disabled={isLoading}
                >
                  Avbryt
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
      <div className="flex items-center justify-between gap-6">
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="p-3 rounded-lg bg-surface-secondary flex-shrink-0">
            <IconPhone className="h-6 w-6 text-text-primary" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="font-semibold text-text-primary">Telefonnummer</h3>
            <p className="text-sm text-text-secondary mt-0.5">
              {hasPhoneConnected
                ? `Du har koblet til telefonnummer ${formatPhoneForDisplay(phoneNumber || '')}`
                : 'Koble til telefonnummeret ditt for enklere pålogging'}
            </p>
            {error && <p className="text-sm text-destructive mt-2">{error}</p>}
          </div>
        </div>
        <Button
          variant={hasPhoneConnected ? 'outline' : 'default'}
          onClick={
            hasPhoneConnected ? handleUnlink : () => setShowLinkForm(true)
          }
          disabled={isLoading}
          className="flex-shrink-0"
        >
          {isLoading
            ? 'Behandler...'
            : hasPhoneConnected
              ? 'Koble fra'
              : 'Koble til'}
        </Button>
      </div>
    </Card>
  );
}
