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
import { deleteShiftsInOtherMonths } from '@/app/(app)/shifts/add/_actions/deleteShiftsInOtherMonths';
import { createCheckoutSession } from '@/app/(app)/settings/subscription/_actions/createCheckoutSession';
import { ENV } from '@/lib/env';

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
  const [isDeleting, setIsDeleting] = useState(false);
  const [isUpgrading, setIsUpgrading] = useState(false);
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
        setError(result.error || 'Kunne ikke slette skift');
        setIsDeleting(false);
        return;
      }

      // Close modal and trigger callback to proceed with shift creation
      onOpenChange(false);
      onDeleteComplete();
    } catch (err) {
      console.error('Error deleting shifts:', err);
      setError('En uventet feil oppstod');
      setIsDeleting(false);
    }
  };

  const handleUpgrade = async () => {
    setIsUpgrading(true);
    setError(null);

    try {
      const result = await createCheckoutSession(ENV.PRO_PRICE_ID!);

      if (result.success && result.url) {
        // Redirect to Stripe checkout
        window.location.href = result.url;
      } else {
        setError(result.error || 'Kunne ikke starte oppgraderingsprosessen');
        setIsUpgrading(false);
      }
    } catch (err) {
      console.error('Error creating checkout session:', err);
      setError('En uventet feil oppstod');
      setIsUpgrading(false);
    }
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
              <DialogTitle className="text-xl mb-2">Du er på gratisplanen</DialogTitle>
              <DialogDescription className="text-sm text-text-secondary">
                Med gratisplanen kan du bare ha skift i én måned av gangen.
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <div className="rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 text-sm">
            <p className="text-text-secondary">
              Du prøver å legge til skift i <strong className="text-text-primary">{formattedTargetMonth}</strong>,
              men har allerede skift i <strong className="text-text-primary">{formattedOtherMonths}</strong>.
            </p>
          </div>

          <p className="text-sm font-semibold text-text-primary">Velg ett av alternativene:</p>

          <div className="space-y-3">
            {/* Upgrade option */}
            <button
              onClick={handleUpgrade}
              disabled={isDeleting || isUpgrading}
              className="w-full text-left rounded-2xl border-2 border-brand-gradientMid/30 bg-gradient-to-br from-brand-gradientStart/5 to-brand-gradientMid/5 p-4 transition hover:border-brand-gradientMid/50 disabled:opacity-50"
            >
              <div className="flex items-start gap-3">
                <Sparkles className="h-5 w-5 text-brand-highlight flex-shrink-0 mt-0.5" />
                <div className="flex-1 min-w-0">
                  <h4 className="font-semibold text-sm">Oppgrader til Pro</h4>
                  <p className="text-xs text-text-secondary mt-1">
                    Lagre skift på tvers av måneder, ubegrenset antall skift
                  </p>
                  <p className="text-sm font-bold text-brand-highlight mt-2">29,90 kr/måned</p>
                </div>
              </div>
            </button>

            {/* Delete option */}
            {!showConfirmDelete ? (
              <button
                onClick={handleDeleteClick}
                disabled={isDeleting || isUpgrading}
                className="w-full text-left rounded-2xl border-2 border-red-500/30 bg-red-500/5 p-4 transition hover:border-red-500/50 hover:bg-red-500/10 disabled:opacity-50"
              >
                <div className="flex items-start gap-3">
                  <Trash2 className="h-5 w-5 text-red-600 dark:text-red-500 flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <h4 className="font-semibold text-sm text-red-900 dark:text-red-300">Slett skift i andre måneder</h4>
                    <p className="text-xs text-red-700 dark:text-red-400 mt-1">
                      Alle skift i {formattedOtherMonths} vil bli permanent slettet
                    </p>
                  </div>
                </div>
              </button>
            ) : (
              <div className="rounded-2xl border-2 border-red-500/50 bg-red-500/10 p-4">
                <div className="flex items-start gap-3 mb-3">
                  <AlertTriangle className="h-5 w-5 text-red-600 dark:text-red-500 flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <h4 className="font-semibold text-sm text-red-900 dark:text-red-300">Er du sikker?</h4>
                    <p className="text-xs text-red-700 dark:text-red-400 mt-1">
                      Dette vil slette alle skift i {formattedOtherMonths} permanent.
                    </p>
                  </div>
                </div>
                <div className="flex gap-2">
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() => setShowConfirmDelete(false)}
                    disabled={isDeleting}
                    className="flex-1 text-xs"
                  >
                    Avbryt
                  </Button>
                  <Button
                    type="button"
                    variant="destructive"
                    onClick={handleDeleteConfirm}
                    disabled={isDeleting}
                    loading={isDeleting}
                    className="flex-1 text-xs"
                  >
                    Slett {deleteCount} {deleteCount === 1 ? 'måned' : 'måneder'}
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
            disabled={isDeleting || isUpgrading}
            className="w-full rounded-xl px-4 py-2"
          >
            Avbryt
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
