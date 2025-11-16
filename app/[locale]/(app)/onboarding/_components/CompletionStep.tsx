"use client";

import { Button } from "@/components/app/Button";
import { Badge } from "@/components/app/Badge";
import { Separator } from "@/components/app/Separator";
import { CheckCircle } from "lucide-react";
import { useTranslations } from "@/lib/i18n/client";

interface CompletionStepProps {
  wageDisplay: string;
  customSupplements: { rules: any[] } | null;
  breakEnabled: boolean;
  breakDuration: string;
  breakThreshold: string;
  taxDeductionEnabled: boolean;
  taxPercentage: string;
  payrollDay: string;
  theme: string;
  onComplete: () => void;
  isSubmitting: boolean;
}

export function CompletionStep({
  wageDisplay,
  customSupplements,
  breakEnabled,
  breakDuration,
  breakThreshold,
  taxDeductionEnabled,
  taxPercentage,
  payrollDay,
  theme,
  onComplete,
  isSubmitting,
}: CompletionStepProps) {
  const { t } = useTranslations();

  return (
    <div className="space-y-6 text-center">
      <div className="flex items-center justify-center">
        <div className="rounded-full bg-success-subtle p-4">
          <CheckCircle className="h-12 w-12 text-success-foreground" />
        </div>
      </div>

      <div className="space-y-4">
        <h2 className="text-2xl font-bold">{t.onboarding.completionStep.title}</h2>
        <p className="text-text-secondary">
          {t.onboarding.completionStep.description}
        </p>
      </div>

      <Separator />

      <div className="space-y-3 text-left">
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">{t.onboarding.completionStep.hourlyWage}</span>
          <Badge variant="secondary">{wageDisplay}</Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">{t.onboarding.completionStep.supplements}</span>
          <Badge variant="secondary">
            {customSupplements && customSupplements.rules.length > 0
              ? t.onboarding.completionStep.supplementsCount.replace('{count}', String(customSupplements.rules.length))
              : t.onboarding.completionStep.noSupplements}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">{t.onboarding.completionStep.breaks}</span>
          <Badge variant="secondary">
            {breakEnabled
              ? t.onboarding.completionStep.breakSummary
                  .replace('{duration}', breakDuration)
                  .replace('{threshold}', breakThreshold)
              : t.onboarding.completionStep.off}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">{t.onboarding.completionStep.taxDeduction}</span>
          <Badge variant="secondary">
            {taxDeductionEnabled ? `${taxPercentage}%` : t.onboarding.completionStep.off}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">{t.onboarding.completionStep.payrollDay}</span>
          <Badge variant="secondary">
            {payrollDay ? t.onboarding.completionStep.dayOfMonth.replace('{day}', payrollDay) : t.onboarding.completionStep.notSet}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">{t.onboarding.completionStep.theme}</span>
          <Badge variant="secondary">{t.onboarding.completionStep.themeLabels[theme as keyof typeof t.onboarding.completionStep.themeLabels] || theme}</Badge>
        </div>
      </div>

      <Separator />

      <Button onClick={onComplete} className="w-full" disabled={isSubmitting}>
        {isSubmitting ? t.onboarding.completionStep.saving : t.onboarding.completionStep.completeButton}
      </Button>
    </div>
  );
}
