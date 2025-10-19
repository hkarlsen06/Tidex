'use client';

import { useState } from 'react';
import { Button } from '@appui/Button';
import { Card } from '@appui/Card';
import { InfoIcon } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipTrigger } from '@appui/Tooltip';
import { SupplementsEditor, SupplementsData } from '@/components/settings/SupplementsEditor';

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
  const [tooltipOpen, setTooltipOpen] = useState(false);

  const handleSkip = () => {
    setCustomSupplements(null);
    onNext();
  };

  // If user is on tariff, skip custom supplements and show info message
  if (wageType === 'preset') {
    return (
      <div className="space-y-6">
        <div className="space-y-2">
          <h2 className="text-2xl font-bold">Tillegg</h2>
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
              setCustomSupplements(null);
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
    customSupplements?.rules && customSupplements.rules.length > 0;

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <div className="flex items-start gap-2">
          <h2 className="text-2xl font-bold">Tillegg</h2>
          <Tooltip open={tooltipOpen} onOpenChange={setTooltipOpen} delayDuration={0}>
            <TooltipTrigger
              asChild
              onPointerDown={(e) => e.preventDefault()}
            >
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  setTooltipOpen(!tooltipOpen);
                }}
                className="touch-manipulation mt-1"
              >
                <InfoIcon className="h-5 w-5 text-text-muted cursor-pointer hover:text-text-primary transition-colors" />
              </button>
            </TooltipTrigger>
            <TooltipContent
              className="max-w-xs bg-surface-primary border-border text-text-primary"
              onPointerDownOutside={() => setTooltipOpen(false)}
              onEscapeKeyDown={() => setTooltipOpen(false)}
            >
              <p>
                Legg til ekstra tillegg som gjelder for bestemte tider og dager.
                For eksempel kveldstillegg eller helgetillegg.
              </p>
            </TooltipContent>
          </Tooltip>
        </div>
        <p className="text-text-secondary">
          Sett opp tillegg som kveldstillegg, helgetillegg, etc.
        </p>
      </div>

      <SupplementsEditor value={customSupplements} onChange={setCustomSupplements} />

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
