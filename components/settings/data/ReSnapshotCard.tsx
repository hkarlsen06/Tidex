'use client';

import { useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Separator } from '@appui/Separator';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@appui/Dialog';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { bulkClearSnapshots } from '@/app/[locale]/(app)/settings/_actions/bulkClearSnapshots';

interface ReSnapshotCardProps {
  t: Dictionary;
}

export function ReSnapshotCard({ t }: ReSnapshotCardProps) {
  const router = useRouter();
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [isUpdating, setIsUpdating] = useState(false);
  const [showConfirmDialog, setShowConfirmDialog] = useState(false);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const dateRangeInvalid = useMemo(() => {
    if (!startDate || !endDate) return false;
    return startDate > endDate;
  }, [startDate, endDate]);

  const canUpdate = Boolean(startDate && endDate && !dateRangeInvalid);

  const handleUpdateClick = () => {
    if (!canUpdate) return;
    setShowConfirmDialog(true);
  };

  const handleConfirmUpdate = async () => {
    if (!canUpdate) return;

    setShowConfirmDialog(false);
    setIsUpdating(true);
    setSuccessMessage(null);
    setErrorMessage(null);

    try {
      const result = await bulkClearSnapshots(startDate, endDate);

      if (result.success) {
        if (result.count === 0) {
          setSuccessMessage(t.pages.settings.data.reSnapshot.noShiftsMessage);
        } else {
          setSuccessMessage(
            t.pages.settings.data.reSnapshot.successMessage.replace('{count}', String(result.count))
          );
        }

        // Reset form
        setStartDate('');
        setEndDate('');

        // Refresh the page data
        router.refresh();
      }
    } catch (error) {
      console.error('Failed to bulk clear snapshots:', error);
      setErrorMessage(t.pages.settings.data.reSnapshot.errors.unexpectedError);
    } finally {
      setIsUpdating(false);
    }
  };

  return (
    <>
      <div className="space-y-6">
        <div className="text-center">
          <h3 className="text-lg font-semibold text-text-muted">
            {t.pages.settings.data.reSnapshot.title}
          </h3>
          <p className="mt-1 text-sm text-text-secondary">
            {t.pages.settings.data.reSnapshot.description}
          </p>
        </div>

        <Separator />

        <div className="space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:gap-4">
            <div className="flex-1 space-y-2">
              <label className="text-sm font-medium text-text-muted">
                {t.pages.settings.data.reSnapshot.startDateLabel}
              </label>
              <Input
                type="date"
                value={startDate}
                max={endDate || undefined}
                onChange={(e) => setStartDate(e.target.value)}
                className="w-full"
              />
            </div>
            <div className="flex-1 space-y-2">
              <label className="text-sm font-medium text-text-muted">
                {t.pages.settings.data.reSnapshot.endDateLabel}
              </label>
              <Input
                type="date"
                value={endDate}
                min={startDate || undefined}
                onChange={(e) => setEndDate(e.target.value)}
                className="w-full"
              />
            </div>
          </div>

          {dateRangeInvalid && (
            <p className="text-sm text-destructive">
              {t.pages.settings.data.reSnapshot.dateRangeError}
            </p>
          )}

          {successMessage && (
            <div className="rounded-md bg-green-50 dark:bg-green-900/10 p-3">
              <p className="text-sm text-green-800 dark:text-green-200">{successMessage}</p>
            </div>
          )}

          {errorMessage && (
            <div className="rounded-md bg-red-50 dark:bg-red-900/10 p-3">
              <p className="text-sm text-red-800 dark:text-red-200">{errorMessage}</p>
            </div>
          )}

          <Button
            onClick={handleUpdateClick}
            disabled={!canUpdate || isUpdating}
            variant="outline"
            className="w-full"
          >
            {isUpdating
              ? t.pages.settings.data.reSnapshot.updating
              : t.pages.settings.data.reSnapshot.button}
          </Button>
        </div>
      </div>

      <Dialog open={showConfirmDialog} onOpenChange={setShowConfirmDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t.pages.settings.data.reSnapshot.confirmTitle}</DialogTitle>
            <DialogDescription>
              {t.pages.settings.data.reSnapshot.confirmMessage
                .replace('{startDate}', startDate)
                .replace('{endDate}', endDate)}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="secondary"
              onClick={() => setShowConfirmDialog(false)}
              disabled={isUpdating}
            >
              {t.pages.settings.data.reSnapshot.cancelButton}
            </Button>
            <Button onClick={handleConfirmUpdate} disabled={isUpdating}>
              {t.pages.settings.data.reSnapshot.confirmButton}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
