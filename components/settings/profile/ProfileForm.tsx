'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Input } from '@appui/Input';
import { Label } from '@appui/Label';
import { Button } from '@appui/Button';
import { Avatar, AvatarFallback, AvatarImage } from '@appui/Avatar';
import { Separator } from '@appui/Separator';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@appui/Dialog';
import { updateProfileSettings, clearAllShifts } from '../../_actions/updateSettings';
import { useRouter } from 'next/navigation';

interface ProfileFormProps {
  initialData: {
    firstName: string;
    email: string;
    profilePictureUrl: string | null;
  };
}

export function ProfileForm({ initialData }: ProfileFormProps) {
  const router = useRouter();
  const [firstName, setFirstName] = useState(initialData.firstName);
  const [isSaving, setIsSaving] = useState(false);
  const [showClearDialog, setShowClearDialog] = useState(false);
  const [isClearing, setIsClearing] = useState(false);

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await updateProfileSettings({ firstName });
      router.refresh();
      // You can add a toast notification here
    } catch (error) {
      console.error('Failed to save profile:', error);
      // You can add error toast here
    } finally {
      setIsSaving(false);
    }
  };

  const handleClearShifts = async () => {
    setIsClearing(true);
    try {
      await clearAllShifts();
      setShowClearDialog(false);
      router.refresh();
      // You can add a success toast here
    } catch (error) {
      console.error('Failed to clear shifts:', error);
      // You can add error toast here
    } finally {
      setIsClearing(false);
    }
  };

  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map(n => n[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  return (
    <>
      <Card className="p-6">
        <div className="space-y-6">
          <div className="space-y-4">
            <div className="flex items-center gap-4">
              <Avatar className="h-20 w-20">
                <AvatarImage src={initialData.profilePictureUrl || undefined} />
                <AvatarFallback className="bg-surface-secondary text-text-primary text-lg">
                  {getInitials(firstName || initialData.email)}
                </AvatarFallback>
              </Avatar>
              <div className="flex-1">
                <h3 className="font-semibold">Profilbilde</h3>
                <p className="text-sm text-text-secondary">
                  Kommer snart
                </p>
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="firstName">Navn</Label>
              <Input
                id="firstName"
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                placeholder="Ditt navn"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="email">E-post</Label>
              <Input
                id="email"
                value={initialData.email}
                disabled
                className="opacity-60"
              />
              <p className="text-xs text-text-secondary">
                E-postadressen kan ikke endres
              </p>
            </div>
          </div>

          <div className="flex justify-end">
            <Button onClick={handleSave} disabled={isSaving}>
              {isSaving ? 'Lagrer...' : 'Lagre endringer'}
            </Button>
          </div>
        </div>
      </Card>

      <Card className="p-6 border-red-200 dark:border-red-900">
        <div className="space-y-4">
          <div>
            <h3 className="font-semibold text-red-600 dark:text-red-400">Faresone</h3>
            <p className="text-sm text-text-secondary mt-1">
              Irreversible handlinger
            </p>
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <h4 className="font-medium">Slett alle vakter</h4>
              <p className="text-sm text-text-secondary">
                Dette vil permanent slette alle dine registrerte vakter
              </p>
            </div>
            <Button
              variant="destructive"
              onClick={() => setShowClearDialog(true)}
            >
              Slett alle
            </Button>
          </div>
        </div>
      </Card>

      <Dialog open={showClearDialog} onOpenChange={setShowClearDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Er du sikker?</DialogTitle>
            <DialogDescription>
              Dette vil permanent slette alle dine vakter. Denne handlingen kan ikke angres.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setShowClearDialog(false)}
              disabled={isClearing}
            >
              Avbryt
            </Button>
            <Button
              variant="destructive"
              onClick={handleClearShifts}
              disabled={isClearing}
            >
              {isClearing ? 'Sletter...' : 'Slett alle vakter'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
