'use client';

import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Card } from '@appui/Card';
import { Label } from '@appui/Label';
import { Input } from '@appui/Input';
import { Switch } from '@appui/Switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@appui/Select';
import { Separator } from '@appui/Separator';
import { updatePaySettings } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';
import { useTranslations } from '@/lib/i18n/client';

interface PayFormProps {
  initialData: any;
}

export function PayForm({ initialData }: PayFormProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const isInitialMount = useRef(true);

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
  const [halfTaxMonth, setHalfTaxMonth] = useState(
    initialData.half_tax_month?.toString() || 'none'
  );

  // Other settings
  const [monthlyGoal, setMonthlyGoal] = useState(
    initialData.monthly_goal?.toString() || '20000'
  );
  const [payrollDay, setPayrollDay] = useState(
    initialData.payroll_day?.toString() || ''
  );

  const saveSettings = useCallback(async () => {
    try {
      await updatePaySettings({
        monthly_goal: monthlyGoal ? parseFloat(monthlyGoal) : null,
        payroll_day: payrollDay ? parseInt(payrollDay) : null,
        pause_deduction_enabled: pauseDeductionEnabled,
        pause_deduction_method: pauseDeductionEnabled ? pauseMethod : null,
        pause_threshold_hours: pauseDeductionEnabled ? parseFloat(pauseThresholdHours) : null,
        pause_deduction_minutes: pauseDeductionEnabled ? parseInt(pauseDeductionMinutes) : null,
        tax_deduction_enabled: taxDeductionEnabled,
        tax_percentage: taxDeductionEnabled ? parseFloat(taxPercentage) : null,
        half_tax_month: taxDeductionEnabled && halfTaxMonth !== 'none' ? parseInt(halfTaxMonth) : null,
      });
      router.refresh();
    } catch (error) {
      console.error('Failed to save pay settings:', error);
    }
  }, [
    monthlyGoal,
    pauseDeductionEnabled,
    pauseDeductionMinutes,
    pauseMethod,
    pauseThresholdHours,
    payrollDay,
    router,
    taxDeductionEnabled,
    taxPercentage,
    halfTaxMonth,
  ]);

  // Auto-save for immediate changes (buttons, switches, selects)
  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }
    saveSettings();
  }, [pauseDeductionEnabled, pauseMethod, saveSettings, taxDeductionEnabled, halfTaxMonth]);

  // Debounced auto-save for text inputs (1 second)
  useEffect(() => {
    if (isInitialMount.current) return;

    const timer = setTimeout(() => {
      saveSettings();
    }, 1000);

    return () => clearTimeout(timer);
  }, [monthlyGoal, pauseDeductionMinutes, pauseThresholdHours, payrollDay, saveSettings, taxPercentage]);


  return (
    <div className="space-y-6">
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

              <div className="space-y-4">
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

                <div className="space-y-2">
                  <Label htmlFor="halfTaxMonth">{t.pages.settings.pay.tax.halfTaxMonthLabel}</Label>
                  <Select value={halfTaxMonth} onValueChange={setHalfTaxMonth}>
                    <SelectTrigger id="halfTaxMonth">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">{t.pages.settings.pay.tax.halfTaxMonthOff}</SelectItem>
                      <SelectItem value="11">{t.pages.settings.pay.tax.halfTaxMonthNovember}</SelectItem>
                      <SelectItem value="12">{t.pages.settings.pay.tax.halfTaxMonthDecember}</SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-xs text-text-secondary">
                    {t.pages.settings.pay.tax.halfTaxMonthDescription}
                  </p>
                </div>
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

    </div>
  );
}
