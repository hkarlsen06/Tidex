'use client';

import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Card } from '@appui/Card';
import { Label } from '@appui/Label';
import { Input } from '@appui/Input';
import { Switch } from '@appui/Switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@appui/Select';
import { Separator } from '@appui/Separator';
import { SupplementsEditor, SupplementsData } from '@/components/settings/SupplementsEditor';
import { updatePaySettings } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';
import { PRESET_WAGE_RATES, PRESET_SUPPLEMENT_RULES } from '@/lib/payroll';
import { IconBuilding, IconAdjustments } from '@tabler/icons-react';
import { cn } from '@/lib/utils';
import { useTranslations } from '@/lib/i18n/client';

interface PayFormProps {
  initialData: any;
}

const TARIFF_SUPPLEMENTS_DATA: SupplementsData = {
  rules: PRESET_SUPPLEMENT_RULES.map((rule) => ({ ...rule })),
};

interface SupplementsCardProps {
  usePreset: boolean;
  customSupplements: SupplementsData | null;
  setCustomSupplements: React.Dispatch<React.SetStateAction<SupplementsData | null>>;
}

function SupplementsCard({ usePreset, customSupplements, setCustomSupplements }: SupplementsCardProps) {
  const { t } = useTranslations();

  return (
    <Card className="p-6">
      <div className="space-y-6">
        <div>
          <h3 className="text-lg font-semibold">{t.pages.settings.pay.supplements.title}</h3>
          <p className="text-sm text-text-secondary mt-1">
            {usePreset
              ? t.pages.settings.pay.supplements.descriptionPreset
              : t.pages.settings.pay.supplements.descriptionCustom}
          </p>
        </div>

        <Separator />

        <SupplementsEditor
          key={usePreset ? 'tariff' : 'custom'}
          value={usePreset ? TARIFF_SUPPLEMENTS_DATA : customSupplements}
          onChange={setCustomSupplements}
          readOnly={usePreset}
        />

        {usePreset && (
          <p className="text-xs text-text-secondary">
            {t.pages.settings.pay.supplements.tariffNote}
          </p>
        )}
      </div>
    </Card>
  );
}

export function PayForm({ initialData }: PayFormProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const isInitialMount = useRef(true);

  // Wage settings
  const [usePreset, setUsePreset] = useState(initialData.use_preset ?? true);
  const [wageLevel, setWageLevel] = useState(initialData.current_wage_level?.toString() || '1');
  const [customWage, setCustomWage] = useState(initialData.custom_wage?.toString() || '200');
  const [customSupplements, setCustomSupplements] = useState<SupplementsData | null>(
    initialData.custom_supplements || null
  );
  const customWageValue = parseFloat(customWage);
  const isCustomWageInvalid =
    !usePreset &&
    (!customWage || Number.isNaN(customWageValue) || customWageValue < 1 || customWageValue > 10000);

  // Break settings
  const [pauseDeductionEnabled, setPauseDeductionEnabled] = useState(
    initialData.pause_deduction_enabled ?? true
  );
  const [pauseMethod, setPauseMethod] = useState(
    initialData.pause_deduction_method || 'proportional'
  );
  const [pauseThresholdHours, setPauseThresholdHours] = useState(
    initialData.pause_threshold_hours?.toString() || '5.5'
  );
  const [pauseDeductionMinutes, setPauseDeductionMinutes] = useState(
    initialData.pause_deduction_minutes?.toString() || '30'
  );

  // Tax settings
  const [taxDeductionEnabled, setTaxDeductionEnabled] = useState(
    initialData.tax_deduction_enabled ?? false
  );
  const [taxPercentage, setTaxPercentage] = useState(
    initialData.tax_percentage?.toString() || '30'
  );

  // Other settings
  const [monthlyGoal, setMonthlyGoal] = useState(
    initialData.monthly_goal?.toString() || '20000'
  );
  const [payrollDay, setPayrollDay] = useState(
    initialData.payroll_day?.toString() || ''
  );

  const saveSettings = useCallback(async () => {
    if (isCustomWageInvalid) {
      return;
    }

    try {
      await updatePaySettings({
        use_preset: usePreset,
        current_wage_level: parseInt(wageLevel),
        custom_wage: customWageValue,
        custom_supplements: customSupplements,
        monthly_goal: monthlyGoal ? parseFloat(monthlyGoal) : null,
        payroll_day: payrollDay ? parseInt(payrollDay) : null,
        pause_deduction_enabled: pauseDeductionEnabled,
        pause_deduction_method: pauseDeductionEnabled ? pauseMethod : null,
        pause_threshold_hours: pauseDeductionEnabled ? parseFloat(pauseThresholdHours) : null,
        pause_deduction_minutes: pauseDeductionEnabled ? parseInt(pauseDeductionMinutes) : null,
        tax_deduction_enabled: taxDeductionEnabled,
        tax_percentage: taxDeductionEnabled ? parseFloat(taxPercentage) : null,
      });
      router.refresh();
    } catch (error) {
      console.error('Failed to save pay settings:', error);
    }
  }, [
    customSupplements,
    customWageValue,
    isCustomWageInvalid,
    monthlyGoal,
    pauseDeductionEnabled,
    pauseDeductionMinutes,
    pauseMethod,
    pauseThresholdHours,
    payrollDay,
    router,
    taxDeductionEnabled,
    taxPercentage,
    usePreset,
    wageLevel,
  ]);

  // Auto-save for immediate changes (buttons, switches, selects)
  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }
    saveSettings();
  }, [customSupplements, pauseDeductionEnabled, pauseMethod, saveSettings, taxDeductionEnabled, usePreset, wageLevel]);

  // Debounced auto-save for text inputs (1 second)
  useEffect(() => {
    if (isInitialMount.current) return;

    const timer = setTimeout(() => {
      saveSettings();
    }, 1000);

    return () => clearTimeout(timer);
  }, [customWage, monthlyGoal, pauseDeductionMinutes, pauseThresholdHours, payrollDay, saveSettings, taxPercentage]);

  const getCurrentWage = () => {
    if (usePreset) {
      const rate = PRESET_WAGE_RATES[wageLevel];
      return `${rate?.toFixed(2) || '0'} ${t.common.perHour}`;
    }
    return `${customWage} ${t.common.perHour}`;
  };


  return (
    <div className="space-y-6">
      {/* Wage Configuration */}
      <Card className="p-6">
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-semibold">{t.pages.settings.pay.wage.title}</h3>
            <p className="text-sm text-text-secondary mt-1">
              {t.pages.settings.pay.wage.description}
            </p>
          </div>

          <Separator />

          <div className="flex gap-4">
            <button
              type="button"
              onClick={() => setUsePreset(true)}
              className={cn(
                'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
                'border-2',
                usePreset
                  ? 'border-text-primary bg-surface-secondary'
                  : 'border-border hover:border-border-subtle hover:bg-surface-primary'
              )}
            >
              <IconBuilding stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.pages.settings.pay.wage.tariffButton}</span>
            </button>

            <button
              type="button"
              onClick={() => setUsePreset(false)}
              className={cn(
                'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
                'border-2',
                !usePreset
                  ? 'border-text-primary bg-surface-secondary'
                  : 'border-border hover:border-border-subtle hover:bg-surface-primary'
              )}
            >
              <IconAdjustments stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.pages.settings.pay.wage.customButton}</span>
            </button>
          </div>

          {usePreset ? (
            <div className="space-y-2">
              <Label htmlFor="wageLevel">{t.pages.settings.pay.wage.wageLevelLabel}</Label>
              <Select value={wageLevel} onValueChange={setWageLevel}>
                <SelectTrigger id="wageLevel">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.keys(PRESET_WAGE_RATES).map((level) => {
                    const levelNum = parseInt(level);
                    let label = `${t.pages.settings.pay.wage.wageLevelPrefix} ${level}`;

                    if (levelNum === -1) {
                      label = t.pages.settings.pay.wage.wageLevelUnder16;
                    } else if (levelNum === -2) {
                      label = t.pages.settings.pay.wage.wageLevel16to18;
                    }

                    return (
                      <SelectItem key={level} value={level}>
                        {label} - {PRESET_WAGE_RATES[level].toFixed(2)} {t.common.perHour}
                      </SelectItem>
                    );
                  })}
                </SelectContent>
              </Select>
            </div>
          ) : (
            <div className="space-y-2">
              <Label htmlFor="customWage">{t.pages.settings.pay.wage.customWageLabel}</Label>
              <Input
                id="customWage"
                type="number"
                min={1}
                max={10000}
                step={0.01}
                invalid={isCustomWageInvalid}
                value={customWage}
                onChange={(e) => setCustomWage(e.target.value)}
              />
            </div>
          )}

          <div className="p-4 bg-surface-primary rounded-lg">
            <p className="text-sm text-text-secondary">{t.pages.settings.pay.wage.currentWage}</p>
            <p className="text-xl font-semibold mt-1">{getCurrentWage()}</p>
          </div>
        </div>
      </Card>

      {/* Supplements - for custom wage users, show here */}
      {!usePreset && (
        <SupplementsCard
          usePreset={usePreset}
          customSupplements={customSupplements}
          setCustomSupplements={setCustomSupplements}
        />
      )}

      {/* Break Deduction */}
      <Card className="p-6">
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-lg font-semibold">{t.pages.settings.pay.breaks.title}</h3>
              <p className="text-sm text-text-secondary mt-1">
                {t.pages.settings.pay.breaks.description}
              </p>
            </div>
            <Switch
              checked={pauseDeductionEnabled}
              onCheckedChange={setPauseDeductionEnabled}
            />
          </div>

          {pauseDeductionEnabled && (
            <>
              <Separator />

              <div className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="pauseMethod">{t.pages.settings.pay.breaks.methodLabel}</Label>
                  <Select value={pauseMethod} onValueChange={setPauseMethod}>
                    <SelectTrigger id="pauseMethod">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="proportional">{t.pages.settings.pay.breaks.methodProportional}</SelectItem>
                      <SelectItem value="base_only">{t.pages.settings.pay.breaks.methodBaseOnly}</SelectItem>
                      <SelectItem value="end_of_shift">{t.pages.settings.pay.breaks.methodEndOfShift}</SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-xs text-text-secondary">
                    {pauseMethod === 'proportional' && t.pages.settings.pay.breaks.methodHelpProportional}
                    {pauseMethod === 'base_only' && t.pages.settings.pay.breaks.methodHelpBaseOnly}
                    {pauseMethod === 'end_of_shift' && t.pages.settings.pay.breaks.methodHelpEndOfShift}
                  </p>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="threshold">{t.pages.settings.pay.breaks.thresholdLabel}</Label>
                    <Input
                      id="threshold"
                      type="number"
                      min={0}
                      step={0.5}
                      value={pauseThresholdHours}
                      onChange={(e) => setPauseThresholdHours(e.target.value)}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="duration">{t.pages.settings.pay.breaks.durationLabel}</Label>
                    <Input
                      id="duration"
                      type="number"
                      min={0}
                      step={15}
                      value={pauseDeductionMinutes}
                      onChange={(e) => setPauseDeductionMinutes(e.target.value)}
                    />
                  </div>
                </div>
              </div>
            </>
          )}
        </div>
      </Card>

      {/* Tax Deduction */}
      <Card className="p-6">
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-lg font-semibold">{t.pages.settings.pay.tax.title}</h3>
              <p className="text-sm text-text-secondary mt-1">
                {t.pages.settings.pay.tax.description}
              </p>
            </div>
            <Switch
              checked={taxDeductionEnabled}
              onCheckedChange={setTaxDeductionEnabled}
            />
          </div>

          {taxDeductionEnabled && (
            <>
              <Separator />

              <div className="space-y-2">
                <Label htmlFor="taxPercentage">{t.pages.settings.pay.tax.percentageLabel}</Label>
                <Input
                  id="taxPercentage"
                  type="number"
                  min={0}
                  max={100}
                  step={0.1}
                  value={taxPercentage}
                  onChange={(e) => setTaxPercentage(e.target.value)}
                />
                <p className="text-xs text-text-secondary">
                  {t.pages.settings.pay.tax.disclaimer}
                </p>
              </div>
            </>
          )}
        </div>
      </Card>

      {/* Other Settings */}
      <Card className="p-6">
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-semibold">{t.pages.settings.pay.other.title}</h3>
            <p className="text-sm text-text-secondary mt-1">
              {t.pages.settings.pay.other.description}
            </p>
          </div>

          <Separator />

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="monthlyGoal">{t.pages.settings.pay.other.monthlyGoalLabel}</Label>
              <Input
                id="monthlyGoal"
                type="number"
                min={0}
                value={monthlyGoal}
                onChange={(e) => setMonthlyGoal(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="payrollDay">{t.pages.settings.pay.other.paymentDayLabel}</Label>
              <Input
                id="payrollDay"
                type="number"
                min={1}
                max={31}
                value={payrollDay}
                onChange={(e) => setPayrollDay(e.target.value)}
                placeholder="1-31"
              />
            </div>
          </div>
        </div>
      </Card>

      {/* Supplements - for tariff users, show at the bottom */}
      {usePreset && (
        <SupplementsCard
          usePreset={usePreset}
          customSupplements={customSupplements}
          setCustomSupplements={setCustomSupplements}
        />
      )}
    </div>
  );
}
