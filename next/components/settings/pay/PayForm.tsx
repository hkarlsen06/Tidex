'use client';

import React, { useState, useEffect, useRef, useCallback, useTransition } from 'react';
import { Card } from '@/components/app/Card';
import { Label } from '@/components/app/Label';
import { Input } from '@/components/app/Input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/app/Select';
import { Separator } from '@/components/app/Separator';
import { updateJobPaySettingsAction } from '@/app/[locale]/(app)/settings/pay/_actions/job-settings';
import { useRouter } from 'next/navigation';
import { useTranslations } from '@/lib/i18n/client';

interface PayFormProps {
  initialData: {
    half_tax_month?: number | null;
    monthly_goal?: number | null;
    payroll_day?: number | null;
  };
  jobId?: string | null;
}

/**
 * PayForm - Job pay settings
 *
 * NOTE: Tax and break deduction settings are handled in wage snapshots.
 * This form handles monthly_goal, payroll_day and half_tax_month for the selected job.
 */
export function PayForm({ initialData, jobId = null }: PayFormProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [_isPending, startTransition] = useTransition();
  const isInitialMount = useRef(true);

  // Global settings (not per-snapshot)
  const [halfTaxMonth, setHalfTaxMonth] = useState(
    initialData.half_tax_month?.toString() || 'none'
  );
  const [monthlyGoal, setMonthlyGoal] = useState(
    initialData.monthly_goal?.toString() || '20000'
  );
  const [payrollDay, setPayrollDay] = useState(
    initialData.payroll_day?.toString() || ''
  );

  const saveSettings = useCallback(async () => {
    startTransition(async () => {
      try {
        await updateJobPaySettingsAction(jobId, {
          monthly_goal: monthlyGoal ? parseFloat(monthlyGoal) : null,
          payroll_day: payrollDay ? parseInt(payrollDay) : null,
          half_tax_month: halfTaxMonth !== 'none' ? parseInt(halfTaxMonth) : null,
        });
        router.refresh();
      } catch (error) {
        console.error('Failed to save pay settings:', error);
      }
    });
  }, [jobId, monthlyGoal, payrollDay, halfTaxMonth, router]);

  // Auto-save for immediate changes (selects)
  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }
    saveSettings();
  }, [halfTaxMonth, saveSettings]);

  // Debounced auto-save for text inputs (1 second)
  useEffect(() => {
    if (isInitialMount.current) return;

    const timer = setTimeout(() => {
      saveSettings();
    }, 1000);

    return () => clearTimeout(timer);
  }, [monthlyGoal, payrollDay, saveSettings]);

  return (
    <div className="space-y-6">
      {/* Job-level settings */}
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

          <Separator />

          {/* Half Tax Month - Global calendar preference */}
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
      </Card>
    </div>
  );
}
