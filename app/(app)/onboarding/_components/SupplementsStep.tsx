'use client';

import { Button } from '@appui/Button';
import { Card } from '@appui/Card';
import { InfoIcon } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@appui/Tooltip';
import { SupplementsEditor, SupplementsData } from '@/components/settings/SupplementsEditor';

interface SupplementsStepProps {
  customBonuses: SupplementsData | null;
  setCustomBonuses: (value: SupplementsData | null) => void;
  wageType: 'preset' | 'custom';
  onNext: () => void;
  onBack: () => void;
}

export function SupplementsStep({
  customBonuses,
  setCustomBonuses,
  wageType,
  onNext,
  onBack,
}: SupplementsStepProps) {
  const handleSkip = () => {
    setCustomBonuses(null);
    onNext();
  };

  // If user is on tariff, skip custom supplements and show info message
  if (wageType === 'preset') {
    return (
      <div className="space-y-6">
        <div className="space-y-2">
          <h2 className="text-2xl font-bold">Egendefinerte tillegg</h2>
          <p className="text-text-secondary">
            Siden du bruker tariffavtale, er tillegg allerede definert i systemet.
          </p>
        </div>

        <Card className="p-6 bg-surface-primary border-brand-gradientStart/20">
          <div className="flex items-start gap-3">
            <InfoIcon className="h-5 w-5 text-brand-gradientStart mt-0.5 flex-shrink-0" />
            <div className="space-y-2">
              <p className="font-medium">Tariffens tillegg gjelder automatisk</p>
              <p className="text-sm text-text-secondary">
                Kveldstillegg, helgetillegg og andre tillegg fra tariffavtalen beregnes automatisk basert på når du jobber.
              </p>
            </div>
          </div>
        </Card>

        <div className="flex gap-3">
          <Button onClick={onBack} variant="outline" className="flex-1">
            Tilbake
          </Button>
          <Button
            onClick={() => {
              setCustomBonuses(null);
              onNext();
            }}
            className="flex-1"
          >
            Neste
          </Button>
        </div>
      </div>
    );
  }

  const hasValidSettings =
    customBonuses?.rules && customBonuses.rules.length > 0;

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <div className="flex items-start gap-2">
          <h2 className="text-2xl font-bold">Egendefinerte tillegg</h2>
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <InfoIcon className="h-5 w-5 text-text-muted mt-1 cursor-help" />
              </TooltipTrigger>
              <TooltipContent className="max-w-xs">
                <p>
                  Legg til ekstra tillegg som gjelder for bestemte tider og dager.
                  For eksempel kveldstillegg eller helgetillegg.
                </p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
        <p className="text-text-secondary">
          Sett opp tillegg som kveldstillegg, helgetillegg, etc. (valgfritt)
        </p>
      </div>

      <SupplementsEditor value={customBonuses} onChange={setCustomBonuses} />

      <div className="flex gap-3">
        <Button onClick={onBack} variant="outline" className="flex-1">
          Tilbake
        </Button>
        <Button
          onClick={handleSkip}
          variant="ghost"
          className="flex-1"
          disabled={hasValidSettings}
        >
          Hopp over
        </Button>
        <Button
          onClick={onNext}
          className="flex-1"
          disabled={!hasValidSettings}
        >
          Neste
        </Button>
      </div>
    </div>
  );
}
