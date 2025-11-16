'use client';

import { useState } from 'react';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Separator } from '@/components/app/Separator';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/app/Dialog';
import { clearAllShifts, restartOnboarding } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';
import { useTranslations } from '@/lib/i18n/client';

export function DangerZone() {
  const { t } = useTranslations();
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
            <h3 className="font-semibold text-red-600 dark:text-red-400">{t.pages.settings.profile.dangerZone.title}</h3>
            <p className="text-sm text-text-secondary mt-1">
              {t.pages.settings.profile.dangerZone.subtitle}
            </p>
          </div>

          <Separator />

          <div className="flex flex-col gap-3 sm:flex-row sm:items-stretch sm:gap-8">
            <div className="space-y-1 sm:w-52 sm:flex-shrink-0">
              <h4 className="font-medium">{t.pages.settings.profile.dangerZone.restartOnboarding.title}</h4>
              <p className="text-sm text-text-secondary">
                {t.pages.settings.profile.dangerZone.restartOnboarding.description}
              </p>
            </div>
            <Button
              variant="outline"
              onClick={() => setShowRestartDialog(true)}
              className="w-full px-4 py-4 sm:w-40 sm:self-stretch"
            >
              {t.pages.settings.profile.dangerZone.restartOnboarding.button}
            </Button>
          </div>

          <Separator />

          <div className="flex flex-col gap-3 sm:flex-row sm:items-stretch sm:gap-8">
            <div className="space-y-1 sm:w-52 sm:flex-shrink-0">
              <h4 className="font-medium">{t.pages.settings.profile.dangerZone.deleteAllShifts.title}</h4>
              <p className="text-sm text-text-secondary">
                {t.pages.settings.profile.dangerZone.deleteAllShifts.description}
              </p>
            </div>
            <Button
              variant="destructive"
              onClick={() => setShowClearDialog(true)}
              className="w-full px-4 py-4 sm:w-40 sm:self-stretch"
            >
              {t.pages.settings.profile.dangerZone.deleteAllShifts.button}
            </Button>
          </div>
        </div>
      </Card>

      <Dialog open={showClearDialog} onOpenChange={setShowClearDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t.pages.settings.profile.dangerZone.deleteAllShifts.dialogTitle}</DialogTitle>
            <DialogDescription>
              {t.pages.settings.profile.dangerZone.deleteAllShifts.dialogDescription}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setShowClearDialog(false)}
              disabled={isClearing}
            >
              {t.common.cancel}
            </Button>
            <Button
              variant="destructive"
              onClick={handleClearShifts}
              disabled={isClearing}
            >
              {isClearing ? t.pages.settings.profile.dangerZone.deleteAllShifts.deleting : t.pages.settings.profile.dangerZone.deleteAllShifts.button}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={showRestartDialog} onOpenChange={setShowRestartDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t.pages.settings.profile.dangerZone.restartOnboarding.dialogTitle}</DialogTitle>
            <DialogDescription>
              {t.pages.settings.profile.dangerZone.restartOnboarding.dialogDescription}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setShowRestartDialog(false)}
              disabled={isRestarting}
            >
              {t.common.cancel}
            </Button>
            <Button
              variant="secondary"
              onClick={handleRestartOnboarding}
              disabled={isRestarting}
            >
              {isRestarting ? t.pages.settings.profile.dangerZone.restartOnboarding.sending : t.pages.settings.profile.dangerZone.restartOnboarding.button}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
