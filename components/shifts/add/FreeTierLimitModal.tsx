'use client';

import { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@appui/Dialog';
import { Button } from '@appui/Button';
import { AlertTriangle, Trash2, Sparkles } from 'lucide-react';
import { formatMonth } from '@/lib/subscription/hasProAccess';
import { deleteShiftsInOtherMonths } from '@/app/[locale]/(app)/shifts/add/_actions/deleteShiftsInOtherMonths';
import { useTranslations } from '@/lib/i18n/client';
import { useRouter } from 'next/navigation';

interface FreeTierLimitModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  existingMonths: string[];
  targetMonth: string;
  onDeleteComplete: () => void;
}

export function FreeTierLimitModal({
  open,
  onOpenChange,
  existingMonths,
  targetMonth,
  onDeleteComplete,
}: FreeTierLimitModalProps) {
  const { t, locale } = useTranslations();
  const router = useRouter();
  const [isDeleting, setIsDeleting] = useState(false);
  const [showConfirmDelete, setShowConfirmDelete] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleDeleteClick = () => {
    setShowConfirmDelete(true);
  };

  const handleDeleteConfirm = async () => {
    setIsDeleting(true);
    setError(null);

    try {
      const result = await deleteShiftsInOtherMonths(targetMonth);

      if (!result.success) {
        setError(result.error || t.pages.shifts.add.freeTierLimit.couldNotDeleteShifts);
        setIsDeleting(false);
        return;
      }

      // Close modal and trigger callback to proceed with shift creation
      onOpenChange(false);
      onDeleteComplete();
    } catch (err) {
      console.error('Error deleting shifts:', err);
      setError(t.pages.shifts.add.freeTierLimit.unexpectedError);
      setIsDeleting(false);
    }
  };

  const handleViewPlans = () => {
    router.push(`/${locale}/settings/subscription`);
  };

  const formattedTargetMonth = formatMonth(targetMonth);

  // Filter out the target month from existing months to avoid repetition
  const otherMonths = existingMonths.filter(m => m !== targetMonth);
  const formattedOtherMonths = otherMonths.map(formatMonth).join(', ');

  // Count how many months will be deleted
  const deleteCount = otherMonths.length;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md rounded-3xl border border-border-subtle bg-surface-primary/95 shadow-app-lg">
        <DialogHeader>
          <div className="flex flex-col items-center text-center gap-3 pb-2">
            <div className="rounded-full bg-yellow-500/10 p-3">
              <AlertTriangle className="h-6 w-6 text-yellow-600 dark:text-yellow-500" />
            </div>
            <div>
              <DialogTitle className="text-xl mb-2">{t.pages.shifts.add.freeTierLimit.title}</DialogTitle>
              <DialogDescription className="text-sm text-text-secondary">
                {t.pages.shifts.add.freeTierLimit.description}
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <div className="rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 text-sm">
            <p className="text-text-secondary">
              {t.pages.shifts.add.freeTierLimit.tryingToAdd}
              <strong className="text-text-primary">{formattedTargetMonth}</strong>
              {t.pages.shifts.add.freeTierLimit.butAlreadyHaveIn}
              <strong className="text-text-primary">{formattedOtherMonths}</strong>.
            </p>
          </div>

          <p className="text-sm font-semibold text-text-primary">{t.pages.shifts.add.freeTierLimit.chooseOption}</p>

          <div className="space-y-3">
            {/* Upgrade option */}
            <button
              onClick={handleViewPlans}
              disabled={isDeleting}
              className="w-full text-left rounded-2xl border-2 border-brand-gradientMid/30 bg-gradient-to-br from-brand-gradientStart/5 to-brand-gradientMid/5 p-4 transition hover:border-brand-gradientMid/50 disabled:opacity-50"
            >
              <div className="flex items-start gap-3">
                <Sparkles className="h-5 w-5 text-brand-highlight flex-shrink-0 mt-0.5" />
                <div className="flex-1 min-w-0">
                  <h4 className="font-semibold text-sm">{t.pages.shifts.add.freeTierLimit.upgradeTitle}</h4>
                  <p className="text-xs text-text-secondary mt-1">
                    {t.pages.shifts.add.freeTierLimit.upgradeDescription}
                  </p>
                </div>
              </div>
            </button>

            {/* Delete option */}
            {!showConfirmDelete ? (
              <button
                onClick={handleDeleteClick}
                disabled={isDeleting}
                className="w-full text-left rounded-2xl border-2 border-red-500/30 bg-red-500/5 p-4 transition hover:border-red-500/50 hover:bg-red-500/10 disabled:opacity-50"
              >
                <div className="flex items-start gap-3">
                  <Trash2 className="h-5 w-5 text-red-600 dark:text-red-500 flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <h4 className="font-semibold text-sm text-red-900 dark:text-red-300">{t.pages.shifts.add.freeTierLimit.deleteTitle}</h4>
                    <p className="text-xs text-red-700 dark:text-red-400 mt-1">
                      {t.pages.shifts.add.freeTierLimit.deleteDescription.replace('{months}', formattedOtherMonths)}
                    </p>
                  </div>
                </div>
              </button>
            ) : (
              <div className="rounded-2xl border-2 border-red-500/50 bg-red-500/10 p-4">
                <div className="flex items-start gap-3 mb-3">
                  <AlertTriangle className="h-5 w-5 text-red-600 dark:text-red-500 flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <h4 className="font-semibold text-sm text-red-900 dark:text-red-300">{t.pages.shifts.add.freeTierLimit.confirmDeleteTitle}</h4>
                    <p className="text-xs text-red-700 dark:text-red-400 mt-1">
                      {t.pages.shifts.add.freeTierLimit.confirmDeleteDescription.replace('{months}', formattedOtherMonths)}
                    </p>
                  </div>
                </div>
                <div className="flex gap-2">
                  <Button
                    type="button"
                    variant="destructive"
                    onClick={handleDeleteConfirm}
                    disabled={isDeleting}
                    loading={isDeleting}
                    className="flex-1 text-xs"
                  >
                    {deleteCount === 1
                      ? t.pages.shifts.add.freeTierLimit.deleteMonths.replace('{count}', '1')
                      : t.pages.shifts.add.freeTierLimit.deleteMonthsPlural.replace('{count}', deleteCount.toString())
                    }
                  </Button>
                  <Button
                    type="button"
                    onClick={() => setShowConfirmDelete(false)}
                    disabled={isDeleting}
                    className="flex-1 text-xs bg-green-600 hover:bg-green-700 text-white"
                  >
                    {t.pages.shifts.add.freeTierLimit.cancel}
                  </Button>
                </div>
              </div>
            )}
          </div>

          {error && (
            <div className="rounded-2xl border border-error/30 bg-error-subtle px-4 py-3 text-sm text-error">
              {error}
            </div>
          )}
        </div>

        <DialogFooter className="pt-2">
          <Button
            type="button"
            variant="ghost"
            onClick={() => onOpenChange(false)}
            disabled={isDeleting}
            className="w-full rounded-xl px-4 py-2"
          >
            {t.pages.shifts.add.freeTierLimit.cancel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
