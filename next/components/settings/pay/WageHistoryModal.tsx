'use client';

import { useState, useTransition, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/app/Dialog';
import { Button } from '@/components/app/Button';
import { Input } from '@/components/app/Input';
import { Label } from '@/components/app/Label';
import { Switch } from '@/components/app/Switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/app/Select';
import { Separator } from '@/components/app/Separator';
import { SupplementsEditor, SupplementsData } from '@/components/settings/SupplementsEditor';
import type { BreakMethod } from '@/lib/payroll/types';
import { WageSourceCard } from '@/components/settings/pay/WageSourceCard';
import { Calendar, AlertTriangle, Trash2, Check, X, ChevronDown, Building } from 'lucide-react';
import {
  createWageSnapshotAction,
  updateWageSnapshotAction,
  deleteWageSnapshotAction,
  getTariffVersionForDateAction,
  getLatestTariffVersionAction,
  getTariffTypesAction,
} from '@/app/[locale]/(app)/settings/pay/_actions/wage-snapshots';
import type { WageSnapshot, SupplementRule } from '@/data-access/wage-snapshots';
import type { TariffVersion, TariffType } from '@/data-access/tariff';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

// Default tariff type for HK Retail agreement
const DEFAULT_TARIFF_TYPE = 'hk_retail';

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
  jobId?: string | null;
  /**
   * Initial tariff version to use when creating new snapshots.
   * If not provided, the modal will fetch the latest version when opened.
   */
  initialTariffVersion?: TariffVersion | null;
}


export function WageHistoryModal({
  isOpen,
  onClose,
  snapshot,
  mode,
  t,
  locale = 'no-NO',
  jobId,
  initialTariffVersion,
}: WageHistoryModalProps) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  // Tariff type and version state
  const [tariffTypes, setTariffTypes] = useState<TariffType[]>([]);
  const [selectedTariffTypeId, setSelectedTariffTypeId] = useState<string>(() =>
    snapshot?.tariff_type_id ?? DEFAULT_TARIFF_TYPE
  );
  const [tariffVersion, setTariffVersion] = useState<TariffVersion | null>(initialTariffVersion ?? null);
  const [loadingTariff, setLoadingTariff] = useState(false);

  // Form state
  const isBaseline = mode === 'edit' && snapshot?.from_date === null;
  const [fromDate, setFromDate] = useState(() => {
    // In create mode, always use today's date (even if prefilling from previous snapshot)
    if (mode === 'create') {
      return new Date().toISOString().split('T')[0];
    }
    // In edit mode, use the snapshot's date (or today if baseline)
    return snapshot && snapshot.from_date !== null ? snapshot.from_date : new Date().toISOString().split('T')[0];
  });
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

  // Fetch tariff types when modal opens
  useEffect(() => {
    if (!isOpen) return;

    const fetchTariffTypes = async () => {
      try {
        const types = await getTariffTypesAction();
        setTariffTypes(types);
        // If no tariff type selected, use default
        if (!selectedTariffTypeId && types.length > 0) {
          const defaultType = types.find((t) => t.is_default) ?? types[0];
          setSelectedTariffTypeId(defaultType.id);
        }
      } catch (err) {
        console.error('Failed to fetch tariff types:', err);
      }
    };

    fetchTariffTypes();
  }, [isOpen, selectedTariffTypeId]);

  // Fetch tariff version when modal opens, tariff type changes, or when editing a snapshot
  useEffect(() => {
    if (!isOpen) return;

    const fetchTariffVersion = async () => {
      setLoadingTariff(true);
      try {
        if (mode === 'edit' && snapshot?.tariff_type_id && snapshot?.from_date) {
          // Editing a snapshot with tariff: get the version for that date
          const version = await getTariffVersionForDateAction(
            snapshot.tariff_type_id,
            snapshot.from_date
          );
          setTariffVersion(version);
        } else if (mode === 'create' && !initialTariffVersion) {
          // Creating new: get the latest version for selected tariff type
          const version = await getLatestTariffVersionAction(selectedTariffTypeId);
          setTariffVersion(version);
        } else if (initialTariffVersion) {
          // Use the provided initial version
          setTariffVersion(initialTariffVersion);
        }
      } catch (err) {
        console.error('Failed to fetch tariff version:', err);
        // tariffVersion stays null - will show loading/error state
      } finally {
        setLoadingTariff(false);
      }
    };

    fetchTariffVersion();
  }, [isOpen, mode, snapshot?.tariff_type_id, snapshot?.from_date, initialTariffVersion, selectedTariffTypeId]);

  // Get the tariff supplements data from the version if available
  const tariffSupplementsData: SupplementsData = tariffVersion?.supplements
    ? { rules: tariffVersion.supplements.rules.map((rule) => ({ ...rule })) }
    : { rules: [] };

  // Tax settings
  const [taxEnabled, setTaxEnabled] = useState(() => snapshot?.tax_enabled ?? false);
  const [taxPercentage, setTaxPercentage] = useState(() =>
    snapshot?.tax_percentage?.toString() ?? '30'
  );

  // Break deduction settings
  const [breakEnabled, setBreakEnabled] = useState(() => snapshot?.break_enabled ?? true);
  const [breakMethod, setBreakMethod] = useState<BreakMethod>(() =>
    snapshot?.break_method ?? 'proportional'
  );
  const [breakThresholdHours, setBreakThresholdHours] = useState(() =>
    snapshot?.break_threshold_hours?.toString() ?? '5.5'
  );
  const [breakDeductionMinutes, setBreakDeductionMinutes] = useState(() =>
    snapshot?.break_deduction_minutes?.toString() ?? '30'
  );

  const [affectedShiftCount, setAffectedShiftCount] = useState<number | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [showSupplementsInView, setShowSupplementsInView] = useState(false);
  const [showTariffSupplements, setShowTariffSupplements] = useState(false);

  const handleClose = () => {
    // Reset form state when closing
    setFromDate('');
    setUsePreset(true);
    setWageLevel('1');
    setCustomWage('200');
    setCustomSupplements(null);
    setTaxEnabled(false);
    setTaxPercentage('30');
    setBreakEnabled(true);
    setBreakMethod('proportional');
    setBreakThresholdHours('5.5');
    setBreakDeductionMinutes('30');
    setError(null);
    setAffectedShiftCount(null);
    setShowSupplementsInView(false);
    setShowTariffSupplements(false);
    setTariffVersion(initialTariffVersion ?? null);
    setSelectedTariffTypeId(DEFAULT_TARIFF_TYPE);
    onClose();
  };

  const handleSave = () => {
    setError(null);

    // Validation: date required for create mode (edit can be baseline)
    if (mode === 'create' && !fromDate) {
      setError(t.pages.settings.pay.wageHistory.modal.errors.dateRequired);
      return;
    }

    // Tariff version is required for preset mode
    if (usePreset && !tariffVersion) {
      setError('Failed to load tariff rates. Please try again.');
      return;
    }

    const wage = usePreset
      ? tariffVersion!.rates[wageLevel]
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
          ...(jobId ? { job_id: jobId } : {}),
          hourly_wage: wage,
          wage_level: usePreset ? parseInt(wageLevel) : null,
          // Save tariff_type_id when using tariff-based wage
          tariff_type_id: usePreset ? selectedTariffTypeId : null,
          supplements: usePreset
            ? convertSupplements(tariffSupplementsData)
            : convertSupplements(customSupplements),
          // Tax settings
          tax_enabled: taxEnabled,
          tax_percentage: taxEnabled ? parseFloat(taxPercentage) : 0,
          // Break deduction settings
          break_enabled: breakEnabled,
          break_method: breakEnabled ? breakMethod : 'none' as BreakMethod,
          break_threshold_hours: breakEnabled ? parseFloat(breakThresholdHours) : 0,
          break_deduction_minutes: breakEnabled ? parseInt(breakDeductionMinutes) : 0,
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
        <DialogContent className="sm:max-w-130 max-h-[90vh] overflow-y-auto overflow-x-hidden">
          <DialogHeader className="pb-2 text-left">
            <DialogTitle className="flex items-center gap-2 text-left">
              <Calendar className="h-5 w-5 text-text-muted shrink-0" />
              <span className="flex-1 min-w-0">{t.pages.settings.pay.currentWageCard.title}</span>
            </DialogTitle>
            <DialogDescription className="text-left">
              {snapshot.from_date === null
                ? t.pages.settings.pay.wageHistory.baselineDescription
                : t.pages.settings.pay.wageHistory.validFrom.replace('{date}', formatDate(snapshot.from_date, locale))}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-6 py-6">
            <WageSourceCard
              usePreset={snapshot.wage_level !== null}
              setUsePreset={() => { }}
              wageLevel={snapshot.wage_level?.toString() || '1'}
              setWageLevel={() => { }}
              customWage={snapshot.hourly_wage.toString()}
              setCustomWage={() => { }}
              disabled={true}
              showCurrentWage={false}
              tariffVersion={tariffVersion}
              labels={{
                tariffButton: t.pages.settings.pay.wageHistory.modal.useTariff,
                customButton: t.pages.settings.pay.wage.customButton,
                wageLevelLabel: t.pages.settings.pay.wageHistory.modal.tariffLevelLabel,
                customWageLabel: t.pages.settings.pay.wageHistory.modal.customWageLabel,
                wageLevelPrefix: t.pages.settings.pay.wage.wageLevelPrefix,
                wageLevelUnder16: t.pages.settings.pay.wage.wageLevelUnder16,
                wageLevel16to18: t.pages.settings.pay.wage.wageLevel16to18,
                perHour: t.common.perHour,
                tariffVersionLabel: t.pages.settings.pay.wageHistory.modal.tariffVersionLabel,
              }}
            />

            {/* Supplements - Collapsible */}
            <div className="space-y-2">
              <button
                type="button"
                onClick={() => setShowSupplementsInView(!showSupplementsInView)}
                className="flex items-center justify-between w-full text-left group"
              >
                <div>
                  <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.supplementsTitle}</h3>
                  <p className="text-sm text-text-secondary mt-1">
                    {snapshot.wage_level !== null
                      ? t.pages.settings.pay.wageHistory.modal.supplementsTariff
                      : t.pages.settings.pay.wageHistory.modal.supplementsCustom}
                  </p>
                </div>
                <ChevronDown
                  className={`h-5 w-5 text-text-muted transition-transform duration-200 ${showSupplementsInView ? 'rotate-180' : ''
                    }`}
                />
              </button>

              {showSupplementsInView && (
                <div className="pt-2">
                  <SupplementsEditor
                    value={snapshot.supplements && snapshot.supplements.rules.length > 0
                      ? snapshot.supplements
                      : (snapshot.wage_level !== null ? tariffSupplementsData : null)}
                    onChange={() => { }}
                    readOnly={true}
                  />
                </div>
              )}
            </div>

            <Separator />

            {/* Break Deduction - View */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.breakTitle}</h3>
                <span className={`text-sm ${snapshot.break_enabled ? 'text-green-600' : 'text-text-muted'}`}>
                  {snapshot.break_enabled ? t.common.on : t.common.off}
                </span>
              </div>
              {snapshot.break_enabled && (
                <p className="text-sm text-text-secondary">
                  {t.pages.settings.pay.breaks.methodLabel}: {
                    snapshot.break_method === 'proportional' ? t.pages.settings.pay.breaks.methodProportional :
                      snapshot.break_method === 'base_only' ? t.pages.settings.pay.breaks.methodBaseOnly :
                        snapshot.break_method === 'end_of_shift' ? t.pages.settings.pay.breaks.methodEndOfShift :
                          t.common.off
                  }
                  {' • '}
                  {t.onboarding.completionStep.breakSummary
                    .replace('{duration}', String(snapshot.break_deduction_minutes))
                    .replace('{threshold}', String(snapshot.break_threshold_hours))}
                </p>
              )}
            </div>

            <Separator />

            {/* Tax Deduction - View */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.taxTitle}</h3>
                <span className={`text-sm ${snapshot.tax_enabled ? 'text-green-600' : 'text-text-muted'}`}>
                  {snapshot.tax_enabled ? t.common.on : t.common.off}
                </span>
              </div>
              {snapshot.tax_enabled && (
                <p className="text-sm text-text-secondary">
                  {snapshot.tax_percentage}% {t.pages.settings.pay.tax.percentageLabel.toLowerCase()}
                </p>
              )}
            </div>
          </div>

          <DialogFooter className="mt-4">
            <div className="grid w-full gap-2 grid-cols-1">
              <Button
                onClick={handleClose}
                className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
              >
                <X className="h-4 w-4" />
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

  const customWageValue = parseFloat(customWage);
  const isCustomWageInvalid =
    !usePreset &&
    (!customWage || Number.isNaN(customWageValue) || customWageValue < 1 || customWageValue > 10000);

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && !pending && handleClose()}>
      <DialogContent
        className="sm:rounded-3xl sm:max-w-130 max-h-[90vh] overflow-y-auto overflow-x-hidden"
      >
        <DialogHeader className="pb-2 text-left">
          <DialogTitle className="flex items-center gap-2 text-left">
            <Calendar className="h-5 w-5 text-text-muted shrink-0" />
            <span className="flex-1 min-w-0">{title}</span>
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-6 py-6">
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

          {/* Tariff Type Selector - show in preset mode when tariff types are loaded */}
          {usePreset && tariffTypes.length > 0 && (
            <div className="space-y-2">
              <Label htmlFor="tariffType">{t.pages.settings.pay.wageHistory.modal.tariffTypeLabel ?? 'Tariffavtale'}</Label>
              <Select
                value={selectedTariffTypeId}
                onValueChange={(value) => {
                  setSelectedTariffTypeId(value);
                  // Reset wage level when switching tariff type
                  setWageLevel('1');
                }}
                disabled={pending || loadingTariff}
              >
                <SelectTrigger id="tariffType">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {tariffTypes.map((type) => (
                    <SelectItem key={type.id} value={type.id}>
                      <div className="flex items-center gap-2">
                        <Building className="h-4 w-4" />
                        <span>{type.display_name}</span>
                      </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {tariffVersion && (
                <div className="flex items-center gap-1 text-xs text-text-muted">
                  <Calendar className="h-3 w-3" />
                  <span>
                    {t.pages.settings.pay.wageHistory.modal.tariffVersionLabel ?? 'Tariff fra'}{' '}
                    {new Date(tariffVersion.effective_date + 'T00:00:00').toLocaleDateString(locale, {
                      year: 'numeric',
                      month: 'long',
                    })}
                  </span>
                </div>
              )}
            </div>
          )}

          <WageSourceCard
            usePreset={usePreset}
            setUsePreset={setUsePreset}
            wageLevel={wageLevel}
            setWageLevel={setWageLevel}
            customWage={customWage}
            setCustomWage={setCustomWage}
            disabled={pending || loadingTariff}
            showCurrentWage={false}
            tariffVersion={tariffVersion}
            labels={{
              tariffButton: t.pages.settings.pay.wageHistory.modal.useTariff,
              customButton: t.pages.settings.pay.wage.customButton,
              wageLevelLabel: t.pages.settings.pay.wageHistory.modal.tariffLevelLabel,
              customWageLabel: t.pages.settings.pay.wageHistory.modal.customWageLabel,
              wageLevelPrefix: t.pages.settings.pay.wage.wageLevelPrefix,
              wageLevelUnder16: t.pages.settings.pay.wage.wageLevelUnder16,
              wageLevel16to18: t.pages.settings.pay.wage.wageLevel16to18,
              perHour: t.common.perHour,
              tariffVersionLabel: t.pages.settings.pay.wageHistory.modal.tariffVersionLabel,
            }}
          />

          <Separator />

          {/* Supplements */}
          <div className="space-y-2">
            {usePreset ? (
              <>
                {/* Tariff supplements - collapsible */}
                <button
                  type="button"
                  onClick={() => setShowTariffSupplements(!showTariffSupplements)}
                  className="flex items-center justify-between w-full text-left group"
                >
                  <div>
                    <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.supplementsTitle}</h3>
                    <p className="text-sm text-text-secondary mt-1">
                      {t.pages.settings.pay.wageHistory.modal.supplementsTariff}
                    </p>
                  </div>
                  <ChevronDown
                    className={`h-5 w-5 text-text-muted transition-transform duration-200 ${showTariffSupplements ? 'rotate-180' : ''
                      }`}
                  />
                </button>

                {showTariffSupplements && (
                  <div className="pt-2 max-w-full">
                    <SupplementsEditor
                      key="tariff"
                      value={tariffSupplementsData}
                      onChange={() => { }}
                      readOnly={true}
                    />
                  </div>
                )}
              </>
            ) : (
              <>
                {/* Custom supplements - always visible */}
                <div>
                  <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.supplementsTitle}</h3>
                  <p className="text-sm text-text-secondary mt-1">
                    {t.pages.settings.pay.wageHistory.modal.supplementsCustom}
                  </p>
                </div>

                <div className="pt-2 max-w-full">
                  <SupplementsEditor
                    key="custom"
                    value={customSupplements}
                    onChange={setCustomSupplements}
                    readOnly={false}
                  />
                </div>
              </>
            )}
          </div>

          <Separator />

          {/* Break Deduction */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.breakTitle}</h3>
                <p className="text-sm text-text-secondary mt-1">
                  {t.pages.settings.pay.wageHistory.modal.breakDescription}
                </p>
              </div>
              <Switch
                checked={breakEnabled}
                onCheckedChange={setBreakEnabled}
                disabled={pending}
              />
            </div>

            {breakEnabled && (
              <div className="space-y-4 pt-2">
                <div className="space-y-2">
                  <Label htmlFor="breakMethod">{t.pages.settings.pay.breaks.methodLabel}</Label>
                  <Select
                    value={breakMethod}
                    onValueChange={(v) => setBreakMethod(v as BreakMethod)}
                    disabled={pending}
                  >
                    <SelectTrigger id="breakMethod">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="proportional">{t.pages.settings.pay.breaks.methodProportional}</SelectItem>
                      <SelectItem value="base_only">{t.pages.settings.pay.breaks.methodBaseOnly}</SelectItem>
                      <SelectItem value="end_of_shift">{t.pages.settings.pay.breaks.methodEndOfShift}</SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-xs text-text-secondary">
                    {breakMethod === 'proportional' && t.pages.settings.pay.breaks.methodHelpProportional}
                    {breakMethod === 'base_only' && t.pages.settings.pay.breaks.methodHelpBaseOnly}
                    {breakMethod === 'end_of_shift' && t.pages.settings.pay.breaks.methodHelpEndOfShift}
                  </p>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="breakThreshold">{t.pages.settings.pay.breaks.thresholdLabel}</Label>
                    <Input
                      id="breakThreshold"
                      type="number"
                      min={0}
                      step={0.5}
                      value={breakThresholdHours}
                      onChange={(e) => setBreakThresholdHours(e.target.value)}
                      disabled={pending}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="breakDuration">{t.pages.settings.pay.breaks.durationLabel}</Label>
                    <Input
                      id="breakDuration"
                      type="number"
                      min={0}
                      step={15}
                      value={breakDeductionMinutes}
                      onChange={(e) => setBreakDeductionMinutes(e.target.value)}
                      disabled={pending}
                    />
                  </div>
                </div>
              </div>
            )}
          </div>

          <Separator />

          {/* Tax Deduction */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-sm font-semibold">{t.pages.settings.pay.wageHistory.modal.taxTitle}</h3>
                <p className="text-sm text-text-secondary mt-1">
                  {t.pages.settings.pay.wageHistory.modal.taxDescription}
                </p>
              </div>
              <Switch
                checked={taxEnabled}
                onCheckedChange={setTaxEnabled}
                disabled={pending}
              />
            </div>

            {taxEnabled && (
              <div className="space-y-2 pt-2">
                <Label htmlFor="taxPercentage">{t.pages.settings.pay.tax.percentageLabel}</Label>
                <Input
                  id="taxPercentage"
                  type="number"
                  min={0}
                  max={100}
                  step={0.1}
                  value={taxPercentage}
                  onChange={(e) => setTaxPercentage(e.target.value)}
                  disabled={pending}
                />
                <p className="text-xs text-text-secondary">
                  {t.pages.settings.pay.tax.disclaimer}
                </p>
              </div>
            )}
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
                <Trash2 className="h-4 w-4" />
                {t.common.delete}
              </Button>
            )}
            <Button
              onClick={handleSave}
              disabled={pending || isCustomWageInvalid}
              className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 gap-2"
            >
              <Check className="h-4 w-4" />
              {pending ? t.pages.settings.pay.wageHistory.modal.saving : mode === 'edit' ? t.pages.settings.pay.wageHistory.modal.save : t.pages.settings.pay.wageHistory.modal.create}
            </Button>
            <Button
              onClick={handleClose}
              disabled={pending}
              className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
            >
              <X className="h-4 w-4" />
              {t.pages.settings.pay.wageHistory.modal.cancel}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>

      {/* Delete Confirmation Dialog */}
      <Dialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
        <DialogContent className="sm:max-w-106.25">
          <DialogHeader className="text-left">
            <DialogTitle className="flex items-center gap-2 text-destructive text-left">
              <AlertTriangle className="h-5 w-5 shrink-0" />
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
                <Trash2 className="h-4 w-4" />
                {t.pages.settings.pay.wageHistory.modal.deleteTitle}
              </Button>
              <Button
                onClick={() => setShowDeleteConfirm(false)}
                disabled={pending}
                className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
              >
                <X className="h-4 w-4" />
                {t.pages.settings.pay.wageHistory.modal.cancel}
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Dialog>
  );
}
