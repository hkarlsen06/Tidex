'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@appui/Dialog';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Label } from '@appui/Label';
import { SupplementsEditor, SupplementsData } from '@/components/settings/SupplementsEditor';
import { WageSourceCard } from '@/components/settings/pay/WageSourceCard';
import { PRESET_WAGE_RATES, PRESET_SUPPLEMENT_RULES } from '@/lib/payroll';
import { IconCalendar, IconAlertTriangle, IconTrash, IconCheck, IconX } from '@tabler/icons-react';
import {
  createWageSnapshotAction,
  updateWageSnapshotAction,
  deleteWageSnapshotAction,
} from '@/app/[locale]/(app)/settings/pay/_actions/wage-snapshots';
import type { WageSnapshot, SupplementRule } from '@/data-access/wage-snapshots';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

/**
 * Format date for display
 */
function formatDate(isoDate: string, locale: string = 'no-NO'): string {
  const date = new Date(isoDate + 'T00:00:00');
  return date.toLocaleDateString(locale, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

interface WageHistoryModalProps {
  isOpen: boolean;
  onClose: () => void;
  snapshot?: WageSnapshot | null; // If provided, edit mode; otherwise create mode
  mode: 'create' | 'edit' | 'view';
  t: Dictionary;
  locale?: string;
}

const TARIFF_SUPPLEMENTS_DATA: SupplementsData = {
  rules: PRESET_SUPPLEMENT_RULES.map((rule) => ({ ...rule })),
};

export function WageHistoryModal({
  isOpen,
  onClose,
  snapshot,
  mode,
  t,
  locale = 'no-NO',
}: WageHistoryModalProps) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  // Form state
  const isBaseline = snapshot?.from_date === null;
  const [fromDate, setFromDate] = useState(() =>
    snapshot && snapshot.from_date !== null ? snapshot.from_date : new Date().toISOString().split('T')[0]
  );
  const [usePreset, setUsePreset] = useState(() =>
    snapshot ? snapshot.wage_level !== null : true
  );
  const [wageLevel, setWageLevel] = useState(() =>
    snapshot ? snapshot.wage_level?.toString() || '1' : '1'
  );
  const [customWage, setCustomWage] = useState(() =>
    snapshot ? snapshot.hourly_wage.toString() : '200'
  );
  const [customSupplements, setCustomSupplements] = useState<SupplementsData | null>(() =>
    snapshot && snapshot.supplements && snapshot.supplements.rules.length > 0
      ? snapshot.supplements
      : null
  );
  const [affectedShiftCount, setAffectedShiftCount] = useState<number | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleClose = () => {
    // Reset form state when closing
    setFromDate('');
    setUsePreset(true);
    setWageLevel('1');
    setCustomWage('200');
    setCustomSupplements(null);
    setError(null);
    setAffectedShiftCount(null);
    onClose();
  };

  const handleSave = () => {
    setError(null);

    // Validation: date required for create mode (edit can be baseline)
    if (mode === 'create' && !fromDate) {
      setError(t.pages.settings.pay.wageHistory.modal.errors.dateRequired);
      return;
    }

    const wage = usePreset
      ? PRESET_WAGE_RATES[wageLevel]
      : parseFloat(customWage);

    if (!wage || wage <= 0) {
      setError(t.pages.settings.pay.wageHistory.modal.errors.invalidWage);
      return;
    }

    startTransition(async () => {
      try {
        // Convert SupplementsData to payroll SupplementRule format
        // SupplementsData has Omit<SupplementRule, 'id'> with string times and optional 'mode'
        // We need to strip 'mode' and ensure from/to are valid HH:MM format
        const convertSupplements = (
          supplementsData: SupplementsData | null
        ): { rules: SupplementRule[] } => {
          if (!supplementsData || !supplementsData.rules) {
            return { rules: [] };
          }

          const cleanedRules: SupplementRule[] = supplementsData.rules.map((rule) => {
            // Remove 'mode' field and ensure proper types
            const { mode: _mode, ...rest } = rule as any;
            return {
              days: rest.days,
              from: rest.from as `${number}:${number}`, // Type assertion for HHMM
              to: rest.to as `${number}:${number}`,     // Type assertion for HHMM
              ...(rest.rate !== undefined && { rate: rest.rate }),
              ...(rest.percent !== undefined && { percent: rest.percent }),
            };
          });

          return { rules: cleanedRules };
        };

        const data = {
          // In create mode: always use date
          // In edit mode: preserve baseline (null) or use date
          from_date: mode === 'create' ? fromDate : (isBaseline ? null : fromDate),
          hourly_wage: wage,
          wage_level: usePreset ? parseInt(wageLevel) : null,
          supplements: usePreset
            ? convertSupplements(TARIFF_SUPPLEMENTS_DATA)
            : convertSupplements(customSupplements),
        };

        const result =
          mode === 'edit' && snapshot
            ? await updateWageSnapshotAction(snapshot.id, data)
            : await createWageSnapshotAction(data);

        if ('error' in result) {
          setError(result.error);
          return;
        }

        router.refresh();
        handleClose();
      } catch (err) {
        console.error('Failed to save wage snapshot:', err);
        setError(t.pages.settings.pay.wageHistory.modal.errors.unexpectedError);
      }
    });
  };

  const handleDeleteClick = () => {
    setShowDeleteConfirm(true);
  };

  const handleDeleteConfirm = () => {
    if (!snapshot) return;

    setError(null);
    setShowDeleteConfirm(false);

    startTransition(async () => {
      try {
        const result = await deleteWageSnapshotAction(snapshot.id);

        if ('error' in result) {
          setError(result.error);
          return;
        }

        setAffectedShiftCount(result.affectedShiftCount);

        // Close after showing affected count briefly
        setTimeout(() => {
          router.refresh();
          handleClose();
        }, 1500);
      } catch (err) {
        console.error('Failed to delete wage snapshot:', err);
        setError(t.pages.settings.pay.wageHistory.modal.errors.unexpectedError);
      }
    });
  };

  // View-only dialog
  if (mode === 'view' && snapshot) {
    return (
      <Dialog open={isOpen} onOpenChange={(open) => !open && handleClose()}>
        <DialogContent className="sm:rounded-3xl sm:max-w-[520px] max-h-[90vh] overflow-y-auto overflow-x-hidden">
          <DialogHeader>
            <DialogTitle className="flex items-start gap-2">
              <IconCalendar className="h-5 w-5 text-text-muted flex-shrink-0 mt-0.5" />
              <span className="flex-1 min-w-0">{t.pages.settings.pay.currentWageCard.title}</span>
            </DialogTitle>
            <DialogDescription className="text-left">
              {snapshot.from_date === null
                ? t.pages.settings.pay.wageHistory.baselineDescription
                : t.pages.settings.pay.wageHistory.validFrom.replace('{date}', formatDate(snapshot.from_date, locale))}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-6 py-4">
            <WageSourceCard
              usePreset={snapshot.wage_level !== null}
              setUsePreset={() => {}}
              wageLevel={snapshot.wage_level?.toString() || '1'}
              setWageLevel={() => {}}
              customWage={snapshot.hourly_wage.toString()}
              setCustomWage={() => {}}
              disabled={true}
              showCurrentWage={false}
              labels={{
                tariffButton: t.pages.settings.pay.wageHistory.modal.useTariff,
                customButton: t.common.cancel, // Reusing generic label
                wageLevelLabel: t.pages.settings.pay.wageHistory.modal.tariffLevelLabel,
                customWageLabel: t.pages.settings.pay.wageHistory.modal.customWageLabel,
                wageLevelPrefix: t.pages.settings.pay.wage.wageLevelPrefix,
                wageLevelUnder16: t.pages.settings.pay.wage.wageLevelUnder16,
                wageLevel16to18: t.pages.settings.pay.wage.wageLevel16to18,
                perHour: t.common.perHour,
              }}
            />

            {/* Supplements */}
            <div className="space-y-4">
              <div>
                <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.supplementsTitle}</h3>
                <p className="text-sm text-text-secondary mt-1">
                  {snapshot.wage_level !== null
                    ? t.pages.settings.pay.wageHistory.modal.supplementsTariff
                    : t.pages.settings.pay.wageHistory.modal.supplementsCustom}
                </p>
              </div>

              <SupplementsEditor
                value={snapshot.supplements && snapshot.supplements.rules.length > 0
                  ? snapshot.supplements
                  : (snapshot.wage_level !== null ? TARIFF_SUPPLEMENTS_DATA : null)}
                onChange={() => {}}
                readOnly={true}
              />
            </div>
          </div>

          <DialogFooter className="mt-4">
            <div className="grid w-full gap-2 grid-cols-1">
              <Button
                onClick={handleClose}
                className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
              >
                <IconX className="h-4 w-4" />
                {t.common.close}
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }

  // Create/Edit dialog
  const title = mode === 'edit'
    ? t.pages.settings.pay.wageHistory.modal.editTitle
    : t.pages.settings.pay.wageHistory.modal.createTitle;
  const description =
    mode === 'edit'
      ? t.pages.settings.pay.wageHistory.modal.editDescription
      : t.pages.settings.pay.wageHistory.modal.createDescription;

  const customWageValue = parseFloat(customWage);
  const isCustomWageInvalid =
    !usePreset &&
    (!customWage || Number.isNaN(customWageValue) || customWageValue < 1 || customWageValue > 10000);

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && !pending && handleClose()}>
      <DialogContent className="sm:rounded-3xl sm:max-w-[520px] max-h-[90vh] overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-start gap-2">
            <IconCalendar className="h-5 w-5 text-text-muted flex-shrink-0 mt-0.5" />
            <span className="flex-1 min-w-0">{title}</span>
          </DialogTitle>
          <DialogDescription className="text-left">{description}</DialogDescription>
        </DialogHeader>

        <div className="space-y-6 py-4">
          {/* Date input or baseline indicator */}
          {mode === 'edit' && isBaseline ? (
            <div className="rounded-md bg-blue-50 dark:bg-blue-900/10 p-3">
              <p className="text-sm text-blue-800 dark:text-blue-200">
                {t.pages.settings.pay.wageHistory.baselineDescription}
              </p>
            </div>
          ) : (
            <div className="space-y-2">
              <Label htmlFor="fromDate">{t.pages.settings.pay.wageHistory.modal.fromDateLabel}</Label>
              <Input
                id="fromDate"
                type="date"
                value={fromDate}
                onChange={(e) => setFromDate(e.target.value)}
                disabled={pending}
              />
              <p className="text-xs text-text-secondary">
                {t.pages.settings.pay.wageHistory.modal.fromDateHelp}
              </p>
            </div>
          )}

          <WageSourceCard
            usePreset={usePreset}
            setUsePreset={setUsePreset}
            wageLevel={wageLevel}
            setWageLevel={setWageLevel}
            customWage={customWage}
            setCustomWage={setCustomWage}
            disabled={pending}
            showCurrentWage={false}
            labels={{
              tariffButton: t.pages.settings.pay.wageHistory.modal.useTariff,
              customButton: t.common.cancel, // Reusing generic label
              wageLevelLabel: t.pages.settings.pay.wageHistory.modal.tariffLevelLabel,
              customWageLabel: t.pages.settings.pay.wageHistory.modal.customWageLabel,
              wageLevelPrefix: t.pages.settings.pay.wage.wageLevelPrefix,
              wageLevelUnder16: t.pages.settings.pay.wage.wageLevelUnder16,
              wageLevel16to18: t.pages.settings.pay.wage.wageLevel16to18,
              perHour: t.common.perHour,
            }}
          />

          {/* Save Button */}
          <div className="flex justify-end">
            <Button
              onClick={handleSave}
              disabled={pending || isCustomWageInvalid}
              className="w-full sm:w-auto"
            >
              {pending ? t.pages.settings.pay.wageHistory.modal.saving : mode === 'edit' ? t.pages.settings.pay.wageHistory.modal.save : t.pages.settings.pay.wageHistory.modal.create}
            </Button>
          </div>

          {/* Supplements */}
          <div className="space-y-4">
            <div>
              <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.supplementsTitle}</h3>
              <p className="text-sm text-text-secondary mt-1">
                {usePreset
                  ? t.pages.settings.pay.wageHistory.modal.supplementsTariff
                  : t.pages.settings.pay.wageHistory.modal.supplementsCustom}
              </p>
            </div>

            <div className="max-w-full">
              <SupplementsEditor
                key={usePreset ? 'tariff' : 'custom'}
                value={usePreset ? TARIFF_SUPPLEMENTS_DATA : customSupplements}
                onChange={setCustomSupplements}
                readOnly={usePreset}
              />
            </div>
          </div>

          {error && (
            <div className="rounded-md bg-red-50 dark:bg-red-900/10 p-3">
              <p className="text-sm text-red-800 dark:text-red-200">{error}</p>
            </div>
          )}
        </div>

        <DialogFooter className="mt-4">
          <div className={`grid w-full gap-2 ${mode === 'edit' && !isBaseline ? 'grid-cols-3' : 'grid-cols-2'}`}>
            {mode === 'edit' && !isBaseline && (
              <Button
                onClick={handleDeleteClick}
                disabled={pending}
                className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium transition-colors gap-2 bg-rose-600 text-white hover:bg-rose-700"
              >
                <IconTrash className="h-4 w-4" />
                {t.common.delete}
              </Button>
            )}
            <Button
              onClick={handleSave}
              disabled={pending || isCustomWageInvalid}
              className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 gap-2"
            >
              <IconCheck className="h-4 w-4" />
              {pending ? t.pages.settings.pay.wageHistory.modal.saving : mode === 'edit' ? t.pages.settings.pay.wageHistory.modal.save : t.pages.settings.pay.wageHistory.modal.create}
            </Button>
            <Button
              onClick={handleClose}
              disabled={pending}
              className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
            >
              <IconX className="h-4 w-4" />
              {t.pages.settings.pay.wageHistory.modal.cancel}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>

      {/* Delete Confirmation Dialog */}
      <Dialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
        <DialogContent className="sm:rounded-3xl sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle className="flex items-start gap-2 text-destructive">
              <IconAlertTriangle className="h-5 w-5 flex-shrink-0 mt-0.5" />
              <span className="flex-1 min-w-0">{t.pages.settings.pay.wageHistory.modal.deleteTitle}</span>
            </DialogTitle>
            <DialogDescription className="text-left">
              {snapshot?.from_date && t.pages.settings.pay.wageHistory.modal.deleteDescription.replace('{date}', formatDate(snapshot.from_date, locale))}
            </DialogDescription>
          </DialogHeader>

          {affectedShiftCount !== null && (
            <div className="rounded-md bg-blue-50 dark:bg-blue-900/10 p-3">
              <p className="text-sm text-blue-800 dark:text-blue-200">
                {affectedShiftCount === 0
                  ? t.pages.settings.pay.wageHistory.modal.noShiftsAffected
                  : t.pages.settings.pay.wageHistory.modal.shiftsAffected.replace('{count}', affectedShiftCount.toString())}
              </p>
            </div>
          )}

          {error && (
            <div className="rounded-md bg-red-50 dark:bg-red-900/10 p-3">
              <p className="text-sm text-red-800 dark:text-red-200">{error}</p>
            </div>
          )}

          <DialogFooter className="mt-4">
            <div className="grid w-full gap-2 grid-cols-2">
              <Button
                onClick={handleDeleteConfirm}
                disabled={pending}
                loading={pending}
                className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium transition-colors gap-2 bg-rose-600 text-white hover:bg-rose-700"
              >
                <IconTrash className="h-4 w-4" />
                {t.pages.settings.pay.wageHistory.modal.deleteTitle}
              </Button>
              <Button
                onClick={() => setShowDeleteConfirm(false)}
                disabled={pending}
                className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
              >
                <IconX className="h-4 w-4" />
                {t.pages.settings.pay.wageHistory.modal.cancel}
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Dialog>
  );
}
