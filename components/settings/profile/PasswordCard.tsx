'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Label } from '@appui/Label';
import { IconLock } from '@tabler/icons-react';
import { useRouter } from 'next/navigation';
import { setPassword } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { translateError } from '@/lib/errors/translate';
import { useTranslations } from '@/lib/i18n/client';

interface PasswordCardProps {
  hasPassword: boolean;
}

export function PasswordCard({ hasPassword }: PasswordCardProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [password, setPasswordValue] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

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

    setIsLoading(true);

    try {
      await setPassword(password);
      setSuccess(hasPassword ? t.pages.settings.profile.password.success.updated : t.pages.settings.profile.password.success.set);
      setShowPasswordForm(false);
      setPasswordValue('');
      setConfirmPassword('');
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
    setError(null);
    setSuccess(null);
  };

  if (showPasswordForm) {
    return (
      <Card className="p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-4">
            <div className="p-3 rounded-lg bg-surface-secondary flex-shrink-0">
              <IconLock className="h-6 w-6 text-text-primary" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-text-primary">
                {hasPassword ? t.pages.settings.profile.password.titleChange : t.pages.settings.profile.password.titleSet}
              </h3>
              <p className="text-sm text-text-secondary mt-0.5">
                {hasPassword
                  ? t.pages.settings.profile.password.descriptionHasPassword
                  : t.pages.settings.profile.password.descriptionNoPassword}
              </p>
            </div>
          </div>

          <div className="space-y-4">
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

            {error && <p className="text-sm text-destructive">{error}</p>}
            {success && (
              <p className="text-sm text-success-foreground">{success}</p>
            )}

            <div className="flex gap-2">
              <Button
                onClick={handleSetPassword}
                disabled={isLoading || !password || !confirmPassword}
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
          </div>
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="p-3 rounded-lg bg-surface-secondary flex-shrink-0">
            <IconLock className="h-6 w-6 text-text-primary" />
          </div>
          <div className="flex-1 min-w-0">
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
        </div>
        <Button
          variant={hasPassword ? 'outline' : 'default'}
          onClick={() => setShowPasswordForm(true)}
          disabled={isLoading}
          className="w-full sm:w-auto sm:flex-shrink-0"
        >
          {hasPassword ? t.pages.settings.profile.password.change : t.pages.settings.profile.password.set}
        </Button>
      </div>
    </Card>
  );
}
