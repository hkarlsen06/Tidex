'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { Separator } from '@appui/Separator';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@appui/Dialog';
import { clearAllShifts, restartOnboarding } from '@/app/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';

export function DangerZone() {
  const router = useRouter();
  const [showClearDialog, setShowClearDialog] = useState(false);
  const [isClearing, setIsClearing] = useState(false);
  const [showRestartDialog, setShowRestartDialog] = useState(false);
  const [isRestarting, setIsRestarting] = useState(false);

  const handleClearShifts = async () => {
    setIsClearing(true);
    try {
      await clearAllShifts();
      setShowClearDialog(false);
      router.refresh();
    } catch (error) {
      console.error('Failed to clear shifts:', error);
    } finally {
      setIsClearing(false);
    }
  };

  const handleRestartOnboarding = async () => {
    setIsRestarting(true);
    try {
      await restartOnboarding();
      setShowRestartDialog(false);
      router.push('/onboarding');
      router.refresh();
    } catch (error) {
      console.error('Failed to restart onboarding:', error);
    } finally {
      setIsRestarting(false);
    }
  };

  return (
    <>
      <Card className="p-6 border-red-200 dark:border-red-900">
        <div className="space-y-4">
          <div>
            <h3 className="font-semibold text-red-600 dark:text-red-400">Faresone</h3>
            <p className="text-sm text-text-secondary mt-1">
              Irreversible handlinger
            </p>
          </div>

          <Separator />

          <div className="flex flex-col gap-3 sm:flex-row sm:items-stretch sm:gap-8">
            <div className="space-y-1 sm:w-52 sm:flex-shrink-0">
              <h4 className="font-medium">Start onboarding på nytt</h4>
              <p className="text-sm text-text-secondary">
                Nullstill onboarding-status og gå gjennom oppsettet på nytt
              </p>
            </div>
            <Button
              variant="outline"
              onClick={() => setShowRestartDialog(true)}
              className="w-full px-4 py-4 sm:w-40 sm:self-stretch"
            >
              Start på nytt
            </Button>
          </div>

          <Separator />

          <div className="flex flex-col gap-3 sm:flex-row sm:items-stretch sm:gap-8">
            <div className="space-y-1 sm:w-52 sm:flex-shrink-0">
              <h4 className="font-medium">Slett alle vakter</h4>
              <p className="text-sm text-text-secondary">
                Dette vil permanent slette alle dine registrerte vakter
              </p>
            </div>
            <Button
              variant="destructive"
              onClick={() => setShowClearDialog(true)}
              className="w-full px-4 py-4 sm:w-40 sm:self-stretch"
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

      <Dialog open={showRestartDialog} onOpenChange={setShowRestartDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Start onboarding på nytt?</DialogTitle>
            <DialogDescription>
              Du blir sendt tilbake til onboarding-opplegget med forhåndsutfylte innstillinger.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setShowRestartDialog(false)}
              disabled={isRestarting}
            >
              Avbryt
            </Button>
            <Button
              variant="secondary"
              onClick={handleRestartOnboarding}
              disabled={isRestarting}
            >
              {isRestarting ? 'Sender...' : 'Start på nytt'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
