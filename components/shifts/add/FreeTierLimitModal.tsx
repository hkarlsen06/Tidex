'use client';

import { useState, useEffect } from 'react';
import {
  Dialog,
  DialogContent,
  DialogTitle,
} from '@/components/app/Dialog';
import { Button } from '@/components/app/Button';
import { AlertTriangle, Trash2, Sparkles, Check } from 'lucide-react';
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
  const [showDeleteSection, setShowDeleteSection] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Reset state when modal opens
  useEffect(() => {
    if (open) {
      // Note: These setState calls are intentional to reset UI state when the modal opens
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setShowDeleteSection(false);
      setShowConfirmDelete(false);
      setError(null);
    }
  }, [open]);

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

      // Refresh router to show updated data immediately after deletion
      router.refresh();

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
    onOpenChange(false);
    // Small delay to ensure modal closes before navigation
    setTimeout(() => {
      router.push(`/${locale}/settings/subscription`);
    }, 100);
  };

  const formattedTargetMonth = formatMonth(targetMonth);

  // Filter out the target month from existing months to avoid repetition
  const otherMonths = existingMonths.filter(m => m !== targetMonth);
  const formattedOtherMonths = otherMonths.map(formatMonth).join(', ');

  // Count how many months will be deleted
  const deleteCount = otherMonths.length;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideCloseButton className="max-w-[90vw] sm:max-w-sm rounded-3xl border-0 bg-surface-primary p-0 shadow-2xl overflow-hidden">
        <DialogTitle className="sr-only">
          {t.pages.shifts.add.freeTierLimit.upgradeHeadline}
        </DialogTitle>
        {/* Hero section with gradient background */}
        <div className="relative overflow-hidden bg-gradient-to-br from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-6 pb-8 pt-12 text-center">
          {/* Decorative elements */}
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,rgba(255,255,255,0.1),transparent_50%)]" />
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_70%_80%,rgba(255,255,255,0.08),transparent_50%)]" />

          {/* Icon */}
          <div className="relative mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-full bg-white/20 shadow-lg backdrop-blur-sm">
            <Sparkles className="h-10 w-10 text-white" strokeWidth={2} />
          </div>

          {/* Title */}
          <h2 className="relative mb-2 text-2xl font-bold text-white">
            {t.pages.shifts.add.freeTierLimit.upgradeHeadline}
          </h2>
          <p className="relative text-sm text-white/90">
            {t.pages.shifts.add.freeTierLimit.upgradeSubheadline}
          </p>
        </div>

        {/* Content section */}
        <div className="space-y-6 px-6 py-6">
          {/* Features list */}
          <div className="space-y-3">
            <div className="flex items-start gap-3">
              <div className="flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full bg-brand-gradientMid/10">
                <Check className="h-4 w-4 text-brand-gradientMid" strokeWidth={3} />
              </div>
              <p className="text-sm text-text-primary">
                {t.pages.shifts.add.freeTierLimit.feature1}
              </p>
            </div>
            <div className="flex items-start gap-3">
              <div className="flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full bg-brand-gradientMid/10">
                <Check className="h-4 w-4 text-brand-gradientMid" strokeWidth={3} />
              </div>
              <p className="text-sm text-text-primary">
                {t.pages.shifts.add.freeTierLimit.feature2}
              </p>
            </div>
            <div className="flex items-start gap-3">
              <div className="flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full bg-brand-gradientMid/10">
                <Check className="h-4 w-4 text-brand-gradientMid" strokeWidth={3} />
              </div>
              <p className="text-sm text-text-primary">
                {t.pages.shifts.add.freeTierLimit.feature3}
              </p>
            </div>
          </div>

          {/* Primary CTA */}
          <Button
            onClick={handleViewPlans}
            disabled={isDeleting}
            className="w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd py-6 text-base font-semibold text-white shadow-lg transition hover:shadow-xl disabled:opacity-50"
          >
            {t.pages.shifts.add.freeTierLimit.viewPlansButton}
          </Button>

          {/* Divider with "or" */}
          <div className="relative">
            <div className="absolute inset-0 flex items-center">
              <div className="w-full border-t border-border-subtle" />
            </div>
            <div className="relative flex justify-center text-xs uppercase">
              <span className="bg-surface-primary px-2 text-text-muted">
                {t.pages.shifts.add.freeTierLimit.or}
              </span>
            </div>
          </div>

          {/* Delete section - collapsed by default */}
          {!showDeleteSection ? (
            <button
              onClick={() => setShowDeleteSection(true)}
              disabled={isDeleting}
              className="w-full text-center text-sm font-medium text-text-secondary transition hover:text-text-primary disabled:opacity-50"
            >
              {t.pages.shifts.add.freeTierLimit.deleteShiftsLink}
            </button>
          ) : (
            <div className="space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/50 p-4">
              <div className="flex items-start gap-3">
                <Trash2 className="h-5 w-5 flex-shrink-0 text-text-muted" strokeWidth={2} />
                <div className="flex-1 min-w-0">
                  <h4 className="text-sm font-semibold text-text-primary">
                    {t.pages.shifts.add.freeTierLimit.deleteTitle}
                  </h4>
                  <p className="mt-1 text-xs text-text-secondary">
                    {t.pages.shifts.add.freeTierLimit.deleteExplanation
                      .replace('{targetMonth}', formattedTargetMonth)
                      .replace('{otherMonths}', formattedOtherMonths)}
                  </p>
                </div>
              </div>

              {!showConfirmDelete ? (
                <Button
                  onClick={handleDeleteClick}
                  disabled={isDeleting}
                  variant="outline"
                  className="w-full rounded-full border-error/30 text-error hover:bg-error/10 hover:border-error/50"
                >
                  {t.pages.shifts.add.freeTierLimit.deleteButton}
                </Button>
              ) : (
                <div className="space-y-3 rounded-xl border border-error/30 bg-error/5 p-3">
                  <div className="flex items-start gap-2">
                    <AlertTriangle className="h-4 w-4 flex-shrink-0 text-error" />
                    <p className="text-xs font-medium text-error">
                      {t.pages.shifts.add.freeTierLimit.confirmDeleteMessage.replace('{months}', formattedOtherMonths)}
                    </p>
                  </div>
                  <div className="flex gap-2">
                    <Button
                      type="button"
                      onClick={() => setShowConfirmDelete(false)}
                      disabled={isDeleting}
                      variant="outline"
                      className="flex-1 rounded-full text-xs"
                    >
                      {t.pages.shifts.add.freeTierLimit.cancelDelete}
                    </Button>
                    <Button
                      type="button"
                      variant="destructive"
                      onClick={handleDeleteConfirm}
                      disabled={isDeleting}
                      loading={isDeleting}
                      className="flex-1 rounded-full text-xs"
                    >
                      {deleteCount === 1
                        ? t.pages.shifts.add.freeTierLimit.confirmDeleteButton.replace('{count}', '1')
                        : t.pages.shifts.add.freeTierLimit.confirmDeleteButtonPlural.replace('{count}', deleteCount.toString())
                      }
                    </Button>
                  </div>
                </div>
              )}

              {error && (
                <div className="rounded-xl border border-error/30 bg-error-subtle px-3 py-2 text-xs text-error">
                  {error}
                </div>
              )}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
