'use client';

import { useState, useEffect, useRef } from 'react';
import { Card } from '@appui/Card';
import { Label } from '@appui/Label';
import { Input } from '@appui/Input';
import { Switch } from '@appui/Switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@appui/Select';
import { Separator } from '@appui/Separator';
import { SupplementsEditor, SupplementsData } from '@/components/settings/SupplementsEditor';
import { updatePaySettings } from '@/app/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';
import { PRESET_WAGE_RATES } from '@/lib/payroll/calc';
import { IconBuilding, IconAdjustments } from '@tabler/icons-react';
import { cn } from '@/lib/utils';

interface PayFormProps {
  initialData: any;
}

export function PayForm({ initialData }: PayFormProps) {
  const router = useRouter();
  const isInitialMount = useRef(true);

  // Wage settings
  const [usePreset, setUsePreset] = useState(initialData.use_preset ?? true);
  const [wageLevel, setWageLevel] = useState(initialData.current_wage_level?.toString() || '1');
  const [customWage, setCustomWage] = useState(initialData.custom_wage?.toString() || '200');
  const [customBonuses, setCustomBonuses] = useState<SupplementsData | null>(
    initialData.custom_bonuses || null
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

  const [isSaving, setIsSaving] = useState(false);

  const saveSettings = async () => {
    if (isCustomWageInvalid) {
      return;
    }

    setIsSaving(true);
    try {
      await updatePaySettings({
        use_preset: usePreset,
        current_wage_level: parseInt(wageLevel),
        custom_wage: customWageValue,
        custom_bonuses: customBonuses,
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
    } finally {
      setIsSaving(false);
    }
  };

  // Auto-save for immediate changes (buttons, switches, selects)
  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }
    saveSettings();
  }, [usePreset, wageLevel, pauseMethod, pauseDeductionEnabled, taxDeductionEnabled, customBonuses]);

  // Debounced auto-save for text inputs (1 second)
  useEffect(() => {
    if (isInitialMount.current) return;

    const timer = setTimeout(() => {
      saveSettings();
    }, 1000);

    return () => clearTimeout(timer);
  }, [customWage, pauseThresholdHours, pauseDeductionMinutes, taxPercentage, monthlyGoal, payrollDay]);

  const getCurrentWage = () => {
    if (usePreset) {
      const rate = PRESET_WAGE_RATES[wageLevel];
      return `${rate?.toFixed(2) || '0'} kr/t`;
    }
    return `${customWage} kr/t`;
  };

  return (
    <div className="space-y-6">
      {/* Wage Configuration */}
      <Card className="p-6">
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-semibold">Grunnlønn</h3>
            <p className="text-sm text-text-secondary mt-1">
              Velg mellom tariff eller egendefinert timelønn
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
              <span className="text-xs font-medium">Tariff</span>
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
              <span className="text-xs font-medium">Egendefinert</span>
            </button>
          </div>

          {usePreset ? (
            <div className="space-y-2">
              <Label htmlFor="wageLevel">Tariffnivå</Label>
              <Select value={wageLevel} onValueChange={setWageLevel}>
                <SelectTrigger id="wageLevel">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.keys(PRESET_WAGE_RATES).map((level) => {
                    const levelNum = parseInt(level);
                    let label = `Nivå ${level}`;

                    if (levelNum === -1) {
                      label = 'Under 16 år';
                    } else if (levelNum === -2) {
                      label = '16 - 18 år';
                    }

                    return (
                      <SelectItem key={level} value={level}>
                        {label} - {PRESET_WAGE_RATES[level].toFixed(2)} kr/t
                      </SelectItem>
                    );
                  })}
                </SelectContent>
              </Select>
            </div>
          ) : (
            <div className="space-y-2">
              <Label htmlFor="customWage">Timelønn (kr)</Label>
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
            <p className="text-sm text-text-secondary">Din nåværende lønn:</p>
            <p className="text-xl font-semibold mt-1">{getCurrentWage()}</p>
          </div>
        </div>
      </Card>

      {/* Custom Supplements - only for custom wage */}
      {!usePreset && (
        <Card className="p-6">
          <div className="space-y-6">
            <div>
              <h3 className="text-lg font-semibold">Egendefinerte tillegg</h3>
              <p className="text-sm text-text-secondary mt-1">
                Legg til tillegg for bestemte tider og dager
              </p>
            </div>

            <Separator />

            <SupplementsEditor value={customBonuses} onChange={setCustomBonuses} />
          </div>
        </Card>
      )}

      {/* Break Deduction */}
      <Card className="p-6">
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-lg font-semibold">Pausetrekk</h3>
              <p className="text-sm text-text-secondary mt-1">
                Automatisk trekk for pauser
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
                  <Label htmlFor="pauseMethod">Trekkmetode</Label>
                  <Select value={pauseMethod} onValueChange={setPauseMethod}>
                    <SelectTrigger id="pauseMethod">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="proportional">Proporsjonal</SelectItem>
                      <SelectItem value="base_only">Kun grunnlønn</SelectItem>
                      <SelectItem value="end_of_shift">Slutt av vakt</SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-xs text-text-secondary">
                    {pauseMethod === 'proportional' && 'Trekker pause proporsjonal basert på vaktlengde'}
                    {pauseMethod === 'base_only' && 'Trekker pause kun fra grunnlønn'}
                    {pauseMethod === 'end_of_shift' && 'Trekker pause fra slutten av vakten'}
                  </p>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="threshold">Terskel (timer)</Label>
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
                    <Label htmlFor="duration">Varighet (min)</Label>
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
              <h3 className="text-lg font-semibold">Skattetrekk</h3>
              <p className="text-sm text-text-secondary mt-1">
                Vis lønn etter skattetrekk
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
                <Label htmlFor="taxPercentage">Skattesats (%)</Label>
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
                  Dette er kun for visning - faktisk skatt kan variere
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
            <h3 className="text-lg font-semibold">Andre innstillinger</h3>
            <p className="text-sm text-text-secondary mt-1">
              Månedsmål og utbetalingsdato
            </p>
          </div>

          <Separator />

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="monthlyGoal">Månedsmål (kr)</Label>
              <Input
                id="monthlyGoal"
                type="number"
                min={0}
                value={monthlyGoal}
                onChange={(e) => setMonthlyGoal(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="payrollDay">Utbetalingsdag</Label>
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
    </div>
  );
}
