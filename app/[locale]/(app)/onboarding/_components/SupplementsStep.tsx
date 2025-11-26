'use client';

import { Button } from '@/components/app/Button';
import { Card } from '@/components/app/Card';
import { InfoIcon } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipTrigger, TooltipProvider } from '@/components/app/Tooltip';
import { SupplementsEditor, SupplementsData } from '@/components/settings/SupplementsEditor';
import { useTranslations } from '@/lib/i18n/client';

interface SupplementsStepProps {
  customSupplements: SupplementsData | null;
  setCustomSupplements: (value: SupplementsData | null) => void;
  wageType: 'preset' | 'custom';
  onNext: () => void;
  onBack: () => void;
}

export function SupplementsStep({
  customSupplements,
  setCustomSupplements,
  wageType,
  onNext,
  onBack,
}: SupplementsStepProps) {
  const { t } = useTranslations();

  const handleSkip = () => {
    setCustomSupplements(null);
    onNext();
  };

  // If user is on tariff, skip custom supplements and show info message
  if (wageType === 'preset') {
    return (
      <div className="space-y-6">
        <div className="space-y-2">
          <h2 className="text-2xl font-bold">{t.onboarding.supplementsStep.title}</h2>
          <p className="text-text-secondary">
            {t.onboarding.supplementsStep.presetDescription}
          </p>
        </div>

        <Card className="p-6 bg-surface-primary border-brand-gradient-start/20">
          <div className="flex items-start gap-3">
            <InfoIcon className="h-5 w-5 text-brand-gradient-start mt-0.5 shrink-0" />
            <div className="space-y-2">
              <p className="font-medium">{t.onboarding.supplementsStep.presetInfoTitle}</p>
              <p className="text-sm text-text-secondary">
                {t.onboarding.supplementsStep.presetInfoDescription}
              </p>
            </div>
          </div>
        </Card>

        <div className="flex gap-3">
          <Button onClick={onBack} variant="outline" className="flex-1">
            {t.common.back}
          </Button>
          <Button
            onClick={() => {
              setCustomSupplements(null);
              onNext();
            }}
            className="flex-1"
          >
            {t.common.next}
          </Button>
        </div>
      </div>
    );
  }

  const hasValidSettings =
    customSupplements?.rules && customSupplements.rules.length > 0;

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <div className="flex items-start gap-2">
          <h2 className="text-2xl font-bold">{t.onboarding.supplementsStep.title}</h2>
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <button type="button" className="touch-manipulation mt-1">
                  <InfoIcon className="h-5 w-5 text-text-muted cursor-pointer hover:text-text-primary transition-colors" />
                </button>
              </TooltipTrigger>
              <TooltipContent className="max-w-xs">
                <p>{t.onboarding.supplementsStep.tooltipText}</p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
        <p className="text-text-secondary">
          {t.onboarding.supplementsStep.customDescription}
        </p>
      </div>

      <SupplementsEditor value={customSupplements} onChange={setCustomSupplements} />

      <div className="flex gap-3">
        <Button onClick={onBack} variant="outline" className="flex-1">
          {t.common.back}
        </Button>
        <Button
          onClick={handleSkip}
          variant="ghost"
          className="flex-1"
          disabled={hasValidSettings}
        >
          {t.onboarding.supplementsStep.skip}
        </Button>
        <Button
          onClick={onNext}
          className="flex-1"
          disabled={!hasValidSettings}
        >
          {t.common.next}
        </Button>
      </div>
    </div>
  );
}
