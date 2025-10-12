'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Label } from '@appui/Label';
import { IconLock } from '@tabler/icons-react';
import { useRouter } from 'next/navigation';
import { setPassword } from '@/app/(app)/settings/_actions/updateSettings';
import { translateError } from '@/lib/errors/translate';

interface PasswordCardProps {
  hasPassword: boolean;
}

export function PasswordCard({ hasPassword }: PasswordCardProps) {
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
      setError('Fyll inn passord');
      return;
    }

    if (password.length < 6) {
      setError('Passordet må være minst 6 tegn langt');
      return;
    }

    if (password !== confirmPassword) {
      setError('Passordene stemmer ikke overens');
      return;
    }

    setIsLoading(true);

    try {
      await setPassword(password);
      setSuccess(hasPassword ? 'Passord oppdatert!' : 'Passord satt!');
      setShowPasswordForm(false);
      setPasswordValue('');
      setConfirmPassword('');
      router.refresh();
    } catch (err) {
      console.error('Failed to set password:', err);
      setError(
        err instanceof Error
          ? translateError(err.message)
          : 'En feil oppstod'
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
                {hasPassword ? 'Endre passord' : 'Sett passord'}
              </h3>
              <p className="text-sm text-text-secondary mt-0.5">
                {hasPassword
                  ? 'Oppdater ditt passord for pålogging'
                  : 'Sett et passord for å kunne logge inn med passord i tillegg til SMS-kode'}
              </p>
            </div>
          </div>

          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="password">
                {hasPassword ? 'Nytt passord' : 'Passord'}
              </Label>
              <Input
                id="password"
                type="password"
                placeholder="Minst 6 tegn"
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
              <Label htmlFor="confirmPassword">Bekreft passord</Label>
              <Input
                id="confirmPassword"
                type="password"
                placeholder="Skriv inn passordet igjen"
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
                  ? 'Lagrer...'
                  : hasPassword
                    ? 'Oppdater passord'
                    : 'Sett passord'}
              </Button>
              <Button
                variant="outline"
                onClick={handleCancel}
                disabled={isLoading}
              >
                Avbryt
              </Button>
            </div>
          </div>
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between gap-6">
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="p-3 rounded-lg bg-surface-secondary flex-shrink-0">
            <IconLock className="h-6 w-6 text-text-primary" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="font-semibold text-text-primary">Passord</h3>
            <p className="text-sm text-text-secondary mt-0.5">
              {hasPassword
                ? 'Du kan logge inn med passord eller SMS-kode'
                : 'Sett et passord for å kunne logge inn med passord i tillegg til SMS-kode'}
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
          className="flex-shrink-0"
        >
          {hasPassword ? 'Endre' : 'Sett passord'}
        </Button>
      </div>
    </Card>
  );
}
