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
import { clearAllShifts } from '@/app/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';

export function DangerZone() {
  const router = useRouter();
  const [showClearDialog, setShowClearDialog] = useState(false);
  const [isClearing, setIsClearing] = useState(false);

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
