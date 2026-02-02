'use client';

import { useState } from 'react';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Input } from '@/components/app/Input';
import { Label } from '@/components/app/Label';
import { Lock } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { setPassword, requestReauthentication } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { translateError } from '@/lib/errors/translate';
import { useTranslations } from '@/lib/i18n/client';

interface PasswordCardProps {
  hasPassword: boolean;
  isPhoneOnly: boolean;
}

export function PasswordCard({ hasPassword, isPhoneOnly }: PasswordCardProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [password, setPasswordValue] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [otpSent, setOtpSent] = useState(false);

  const handleRequestOtp = async () => {
    setError(null);
    setSuccess(null);
    setIsLoading(true);

    try {
      await requestReauthentication();
      setOtpSent(true);
      setSuccess(t.pages.settings.profile.password.codeSent);
    } catch (err) {
      console.error('Failed to request OTP:', err);
      setError(
        err instanceof Error
          ? translateError(err.message)
          : t.pages.settings.profile.password.errors.genericError
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleSetPassword = async () => {
    setError(null);
    setSuccess(null);

    if (!password) {
      setError(t.pages.settings.profile.password.errors.passwordRequired);
      return;
    }

    if (password.length < 6) {
      setError(t.pages.settings.profile.password.errors.passwordTooShort);
      return;
    }

    if (password !== confirmPassword) {
      setError(t.pages.settings.profile.password.errors.passwordMismatch);
      return;
    }

    // For phone-only users, require OTP
    if (isPhoneOnly) {
      if (!otp) {
        setError(t.pages.settings.profile.password.errors.otpRequired);
        return;
      }
      if (otp.length !== 6 || !/^\d{6}$/.test(otp)) {
        setError(t.pages.settings.profile.password.errors.otpInvalid);
        return;
      }
    }

    setIsLoading(true);

    try {
      await setPassword(password, isPhoneOnly ? otp : undefined);
      setSuccess(hasPassword ? t.pages.settings.profile.password.success.updated : t.pages.settings.profile.password.success.set);
      setShowPasswordForm(false);
      setPasswordValue('');
      setConfirmPassword('');
      setOtp('');
      setOtpSent(false);
      router.refresh();
    } catch (err) {
      console.error('Failed to set password:', err);
      setError(
        err instanceof Error
          ? translateError(err.message)
          : t.pages.settings.profile.password.errors.genericError
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleCancel = () => {
    setShowPasswordForm(false);
    setPasswordValue('');
    setConfirmPassword('');
    setOtp('');
    setOtpSent(false);
    setError(null);
    setSuccess(null);
  };

  if (showPasswordForm) {
    return (
      <Card className="p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-4">
            <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
              <Lock className="h-6 w-6 text-text-primary" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-text-primary">
                {hasPassword ? t.pages.settings.profile.password.titleChange : t.pages.settings.profile.password.titleSet}
              </h3>
              <p className="text-sm text-text-secondary mt-0.5">
                {isPhoneOnly
                  ? t.pages.settings.profile.password.descriptionPhoneOnly
                  : hasPassword
                    ? t.pages.settings.profile.password.descriptionHasPassword
                    : t.pages.settings.profile.password.descriptionNoPassword}
              </p>
            </div>
          </div>

          <div className="space-y-4">
            {/* For phone-only users, show OTP request button first */}
            {isPhoneOnly && !otpSent && (
              <div className="space-y-2">
                <p className="text-sm text-text-secondary">
                  {t.pages.settings.profile.password.descriptionPhoneOnly}
                </p>
                <Button
                  onClick={handleRequestOtp}
                  disabled={isLoading}
                  className="w-full"
                >
                  {isLoading ? t.pages.settings.profile.password.sendingCode : t.pages.settings.profile.password.requestCode}
                </Button>
              </div>
            )}

            {/* Show password fields once OTP is sent (for phone users) or immediately (for others) */}
            {(!isPhoneOnly || otpSent) && (
              <>
                {isPhoneOnly && (
                  <div className="space-y-2">
                    <Label htmlFor="otp">{t.pages.settings.profile.password.otpLabel}</Label>
                    <Input
                      id="otp"
                      type="text"
                      inputMode="numeric"
                      pattern="[0-9]*"
                      maxLength={6}
                      value={otp}
                      onChange={(e) => {
                        const value = e.target.value.replace(/\D/g, '');
                        setOtp(value);
                        setError(null);
                        setSuccess(null);
                      }}
                      disabled={isLoading}
                      placeholder="123456"
                    />
                  </div>
                )}

                <div className="space-y-2">
                  <Label htmlFor="password">
                    {hasPassword ? t.pages.settings.profile.password.newPasswordLabel : t.pages.settings.profile.password.passwordLabel}
                  </Label>
                  <Input
                    id="password"
                    type="password"
                    value={password}
                    onChange={(e) => {
                      setPasswordValue(e.target.value);
                      setError(null);
                      setSuccess(null);
                    }}
                    disabled={isLoading}
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="confirmPassword">{t.pages.settings.profile.password.confirmPasswordLabel}</Label>
                  <Input
                    id="confirmPassword"
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => {
                      setConfirmPassword(e.target.value);
                      setError(null);
                      setSuccess(null);
                    }}
                    disabled={isLoading}
                  />
                </div>
              </>
            )}

            {error && <p className="text-sm text-destructive">{error}</p>}
            {success && (
              <p className="text-sm text-success-foreground">{success}</p>
            )}

            {(!isPhoneOnly || otpSent) && (
              <div className="flex gap-2">
                <Button
                  onClick={handleSetPassword}
                  disabled={isLoading || !password || !confirmPassword || (isPhoneOnly && !otp)}
                  className="flex-1"
                >
                  {isLoading
                    ? t.pages.settings.profile.password.setting
                    : hasPassword
                      ? t.pages.settings.profile.password.update
                      : t.pages.settings.profile.password.set}
                </Button>
                <Button
                  variant="outline"
                  onClick={handleCancel}
                  disabled={isLoading}
                >
                  {t.common.cancel}
                </Button>
              </div>
            )}
          </div>
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="flex items-start gap-4">
        <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
          <Lock className="h-6 w-6 text-text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
            <div className="min-w-0">
              <h3 className="font-semibold text-text-primary">{t.pages.settings.profile.password.titleCard}</h3>
              <p className="text-sm text-text-secondary mt-0.5">
                {hasPassword
                  ? t.pages.settings.profile.password.hasPassword
                  : t.pages.settings.profile.password.noPassword}
              </p>
              {error && <p className="text-sm text-destructive mt-2">{error}</p>}
              {success && (
                <p className="text-sm text-success-foreground mt-2">{success}</p>
              )}
            </div>
            <Button
              variant={hasPassword ? 'outline' : 'default'}
              onClick={() => setShowPasswordForm(true)}
              disabled={isLoading}
              className="w-full sm:w-auto shrink-0"
            >
              {hasPassword ? t.pages.settings.profile.password.change : t.pages.settings.profile.password.set}
            </Button>
          </div>
        </div>
      </div>
    </Card>
  );
}
