'use client';

import { useState } from 'react';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Separator } from '@/components/app/Separator';
import { Input } from '@/components/app/Input';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/app/Dialog';
import { clearAllShifts, deleteUserAccount } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { createPortalSession } from '@/app/[locale]/(app)/settings/subscription/_actions/createPortalSession';
import { useRouter } from 'next/navigation';
import { useTranslations } from '@/lib/i18n/client';

interface DangerZoneProps {
  activeSubscription?: {
    provider: 'stripe' | 'apple' | 'admin_trial';
  } | null;
}

type DeleteStep = 'warning' | 'confirm';

export function DangerZone({ activeSubscription }: DangerZoneProps) {
  const { t, locale } = useTranslations();
  const router = useRouter();

  // Clear shifts state
  const [showClearDialog, setShowClearDialog] = useState(false);
  const [clearConfirmText, setClearConfirmText] = useState('');
  const [isClearing, setIsClearing] = useState(false);
  const [clearError, setClearError] = useState<string | null>(null);

  // Delete account state
  const [showDeleteAccountDialog, setShowDeleteAccountDialog] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');
  const [isDeleting, setIsDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  // Subscription warning step state
  const hasActiveSubscription =
    activeSubscription?.provider &&
    activeSubscription.provider !== 'admin_trial';
  const [deleteStep, setDeleteStep] = useState<DeleteStep>(
    hasActiveSubscription ? 'warning' : 'confirm'
  );
  const [isOpeningPortal, setIsOpeningPortal] = useState(false);

  const handleClearShifts = async () => {
    // Validate confirmation text
    const expectedText = t.pages.settings.profile.dangerZone.deleteAllShifts.confirmPlaceholder;
    if (clearConfirmText !== expectedText) {
      setClearError(t.pages.settings.profile.dangerZone.deleteAllShifts.errors.confirmMismatch);
      return;
    }

    setIsClearing(true);
    setClearError(null);

    try {
      await clearAllShifts();
      setShowClearDialog(false);
      setClearConfirmText('');
      router.refresh();
    } catch (error) {
      console.error('Failed to clear shifts:', error);
      setClearError(t.pages.settings.profile.dangerZone.deleteAllShifts.errors.deleteFailed);
    } finally {
      setIsClearing(false);
    }
  };

  const handleClearDialogClose = (open: boolean) => {
    if (!isClearing) {
      setShowClearDialog(open);
      if (!open) {
        // Reset state when closing
        setClearConfirmText('');
        setClearError(null);
      }
    }
  };

  const handleDeleteAccount = async () => {
    // Validate confirmation text
    const expectedText = t.pages.settings.profile.dangerZone.deleteAccount.confirmPlaceholder;
    if (deleteConfirmText !== expectedText) {
      setDeleteError(t.pages.settings.profile.dangerZone.deleteAccount.errors.confirmMismatch);
      return;
    }

    setIsDeleting(true);
    setDeleteError(null);

    try {
      await deleteUserAccount();
      // Account deleted - redirect to login
      // Use window.location to fully clear state
      window.location.href = `/${locale}/login`;
    } catch (error) {
      console.error('Failed to delete account:', error);
      setDeleteError(t.pages.settings.profile.dangerZone.deleteAccount.errors.deleteFailed);
      setIsDeleting(false);
    }
  };

  const handleDeleteDialogClose = (open: boolean) => {
    if (!isDeleting && !isOpeningPortal) {
      setShowDeleteAccountDialog(open);
      if (!open) {
        // Reset state when closing
        setDeleteConfirmText('');
        setDeleteError(null);
        setDeleteStep(hasActiveSubscription ? 'warning' : 'confirm');
      }
    }
  };

  const handleManageSubscription = async () => {
    // Helper to open URL - tries Capacitor Browser first (iOS in-app browser), falls back to new tab (web)
    const openUrl = async (url: string) => {
      try {
        const { Browser } = await import('@capacitor/browser');
        const { Capacitor } = await import('@capacitor/core');
        if (Capacitor.isNativePlatform()) {
          // Use presentationStyle to force in-app browser overlay on iOS
          await Browser.open({
            url,
            presentationStyle: 'popover',
            toolbarColor: '#000000',
          });
          return true;
        }
      } catch (error) {
        console.error('Browser.open failed:', error);
        // Not on native platform or Browser plugin not available
      }
      // Fallback: open in new tab for web
      window.open(url, '_blank');
      return true;
    };

    if (activeSubscription?.provider === 'apple') {
      const iosDeepLink = 'https://apps.apple.com/account/subscriptions';
      await openUrl(iosDeepLink);
      return;
    }

    // Stripe
    try {
      setIsOpeningPortal(true);
      const result = await createPortalSession();
      if (result.success && result.url) {
        await openUrl(result.url);
      } else {
        setDeleteError(
          result.error ||
            t.pages.settings.profile.dangerZone.deleteAccount.subscriptionWarning
              .portalError
        );
      }
    } catch (error) {
      console.error('Error opening customer portal:', error);
      setDeleteError(
        t.pages.settings.profile.dangerZone.deleteAccount.subscriptionWarning
          .portalError
      );
    } finally {
      setIsOpeningPortal(false);
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

          {/* Delete all shifts */}
          <div className="flex flex-col gap-3 sm:flex-row sm:items-stretch sm:gap-8">
            <div className="space-y-1 sm:w-52 sm:shrink-0">
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

          <Separator />

          {/* Delete account */}
          <div className="flex flex-col gap-3 sm:flex-row sm:items-stretch sm:gap-8">
            <div className="space-y-1 sm:w-52 sm:shrink-0">
              <h4 className="font-medium">{t.pages.settings.profile.dangerZone.deleteAccount.title}</h4>
              <p className="text-sm text-text-secondary">
                {t.pages.settings.profile.dangerZone.deleteAccount.description}
              </p>
            </div>
            <Button
              variant="destructive"
              onClick={() => setShowDeleteAccountDialog(true)}
              className="w-full px-4 py-4 sm:w-40 sm:self-stretch"
            >
              {t.pages.settings.profile.dangerZone.deleteAccount.button}
            </Button>
          </div>
        </div>
      </Card>

      {/* Clear shifts dialog */}
      <Dialog open={showClearDialog} onOpenChange={handleClearDialogClose}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="text-red-600 dark:text-red-400">
              {t.pages.settings.profile.dangerZone.deleteAllShifts.dialogTitle}
            </DialogTitle>
            <DialogDescription asChild>
              <div className="space-y-3">
                <p>{t.pages.settings.profile.dangerZone.deleteAllShifts.dialogDescription}</p>
                <ul className="list-disc list-inside space-y-1 text-sm">
                  <li>{t.pages.settings.profile.dangerZone.deleteAllShifts.bullets.shifts}</li>
                  <li>{t.pages.settings.profile.dangerZone.deleteAllShifts.bullets.recurring}</li>
                  <li>{t.pages.settings.profile.dangerZone.deleteAllShifts.bullets.history}</li>
                </ul>
              </div>
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2 py-2">
            <label htmlFor="clear-confirm" className="text-sm font-medium">
              {t.pages.settings.profile.dangerZone.deleteAllShifts.confirmLabel}
            </label>
            <Input
              id="clear-confirm"
              type="text"
              value={clearConfirmText}
              onChange={(e) => {
                setClearConfirmText(e.target.value);
                setClearError(null);
              }}
              placeholder={t.pages.settings.profile.dangerZone.deleteAllShifts.confirmPlaceholder}
              disabled={isClearing}
              className="font-mono"
              autoComplete="off"
            />
            {clearError && (
              <p className="text-sm text-red-600 dark:text-red-400">{clearError}</p>
            )}
          </div>

          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => handleClearDialogClose(false)}
              disabled={isClearing}
            >
              {t.common.cancel}
            </Button>
            <Button
              variant="destructive"
              onClick={handleClearShifts}
              disabled={isClearing || clearConfirmText !== t.pages.settings.profile.dangerZone.deleteAllShifts.confirmPlaceholder}
            >
              {isClearing ? t.pages.settings.profile.dangerZone.deleteAllShifts.deleting : t.pages.settings.profile.dangerZone.deleteAllShifts.button}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete account dialog */}
      <Dialog open={showDeleteAccountDialog} onOpenChange={handleDeleteDialogClose}>
        <DialogContent>
          {/* Step 1: Subscription warning */}
          {deleteStep === 'warning' && (
            <>
              <DialogHeader>
                <DialogTitle className="text-amber-600 dark:text-amber-400">
                  {t.pages.settings.profile.dangerZone.deleteAccount.subscriptionWarning.title}
                </DialogTitle>
                <DialogDescription asChild>
                  <div className="space-y-3">
                    <p>{t.pages.settings.profile.dangerZone.deleteAccount.subscriptionWarning.description}</p>
                    <div className="p-3 bg-amber-50 dark:bg-amber-900/20 rounded-lg border border-amber-200 dark:border-amber-800">
                      <p className="text-sm text-amber-700 dark:text-amber-300">
                        {activeSubscription?.provider === 'apple'
                          ? t.pages.settings.profile.dangerZone.deleteAccount.subscriptionWarning.appleNote
                          : t.pages.settings.profile.dangerZone.deleteAccount.subscriptionWarning.stripeNote}
                      </p>
                    </div>
                  </div>
                </DialogDescription>
              </DialogHeader>

              {deleteError && (
                <p className="text-sm text-red-600 dark:text-red-400">{deleteError}</p>
              )}

              <DialogFooter className="flex-col gap-2 sm:flex-row">
                <Button
                  variant="outline"
                  onClick={() => handleDeleteDialogClose(false)}
                  disabled={isOpeningPortal}
                >
                  {t.common.cancel}
                </Button>
                <Button
                  variant="outline"
                  onClick={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    handleManageSubscription();
                  }}
                  disabled={isOpeningPortal}
                >
                  {isOpeningPortal
                    ? t.common.loading
                    : t.pages.settings.profile.dangerZone.deleteAccount.subscriptionWarning.manageButton}
                </Button>
                <Button
                  variant="destructive"
                  onClick={() => setDeleteStep('confirm')}
                  disabled={isOpeningPortal}
                >
                  {t.pages.settings.profile.dangerZone.deleteAccount.subscriptionWarning.continueButton}
                </Button>
              </DialogFooter>
            </>
          )}

          {/* Step 2: Confirmation */}
          {deleteStep === 'confirm' && (
            <>
              <DialogHeader>
                <DialogTitle className="text-red-600 dark:text-red-400">
                  {t.pages.settings.profile.dangerZone.deleteAccount.dialogTitle}
                </DialogTitle>
                <DialogDescription asChild>
                  <div className="space-y-3">
                    <p>{t.pages.settings.profile.dangerZone.deleteAccount.dialogDescription}</p>
                    <ul className="list-disc list-inside space-y-1 text-sm">
                      <li>{t.pages.settings.profile.dangerZone.deleteAccount.bullets.shifts}</li>
                      <li>{t.pages.settings.profile.dangerZone.deleteAccount.bullets.settings}</li>
                      <li>{t.pages.settings.profile.dangerZone.deleteAccount.bullets.subscription}</li>
                      <li>{t.pages.settings.profile.dangerZone.deleteAccount.bullets.shares}</li>
                    </ul>
                  </div>
                </DialogDescription>
              </DialogHeader>

              <div className="space-y-2 py-2">
                <label htmlFor="delete-confirm" className="text-sm font-medium">
                  {t.pages.settings.profile.dangerZone.deleteAccount.confirmLabel}
                </label>
                <Input
                  id="delete-confirm"
                  type="text"
                  value={deleteConfirmText}
                  onChange={(e) => {
                    setDeleteConfirmText(e.target.value);
                    setDeleteError(null);
                  }}
                  placeholder={t.pages.settings.profile.dangerZone.deleteAccount.confirmPlaceholder}
                  disabled={isDeleting}
                  className="font-mono"
                  autoComplete="off"
                />
                {deleteError && (
                  <p className="text-sm text-red-600 dark:text-red-400">{deleteError}</p>
                )}
              </div>

              <DialogFooter className="flex-col gap-2 sm:flex-row">
                {hasActiveSubscription && (
                  <Button
                    variant="ghost"
                    onClick={() => setDeleteStep('warning')}
                    disabled={isDeleting}
                  >
                    {t.common.back}
                  </Button>
                )}
                <Button
                  variant="outline"
                  onClick={() => handleDeleteDialogClose(false)}
                  disabled={isDeleting}
                >
                  {t.common.cancel}
                </Button>
                <Button
                  variant="destructive"
                  onClick={handleDeleteAccount}
                  disabled={isDeleting || deleteConfirmText !== t.pages.settings.profile.dangerZone.deleteAccount.confirmPlaceholder}
                >
                  {isDeleting ? t.pages.settings.profile.dangerZone.deleteAccount.deleting : t.pages.settings.profile.dangerZone.deleteAccount.button}
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
