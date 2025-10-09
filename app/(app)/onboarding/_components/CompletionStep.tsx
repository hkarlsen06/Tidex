"use client";

import { Button } from "@appui/Button";
import { Badge } from "@appui/Badge";
import { Separator } from "@appui/Separator";
import { CheckCircle } from "lucide-react";

interface CompletionStepProps {
  wageDisplay: string;
  customBonuses: { rules: any[] } | null;
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
  customBonuses,
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
  const themeLabels: Record<string, string> = {
    light: "Lys",
    dark: "Mørk",
    system: "System",
  };

  return (
    <div className="space-y-6 text-center">
      <div className="flex items-center justify-center">
        <div className="rounded-full bg-success-subtle p-4">
          <CheckCircle className="h-12 w-12 text-success-foreground" />
        </div>
      </div>

      <div className="space-y-4">
        <h2 className="text-2xl font-bold">Alt er klart!</h2>
        <p className="text-text-secondary">
          Her er en oppsummering av dine innstillinger
        </p>
      </div>

      <Separator />

      <div className="space-y-3 text-left">
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">Timelønn</span>
          <Badge variant="secondary">{wageDisplay}</Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">Tillegg</span>
          <Badge variant="secondary">
            {customBonuses && customBonuses.rules.length > 0
              ? `${customBonuses.rules.length} tillegg`
              : "Ingen / Tariff"}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">Pause</span>
          <Badge variant="secondary">
            {breakEnabled ? `${breakDuration} min etter ${breakThreshold} timer` : "Av"}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">Skattetrekk</span>
          <Badge variant="secondary">
            {taxDeductionEnabled ? `${taxPercentage}%` : "Av"}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">Lønningsdag</span>
          <Badge variant="secondary">
            {payrollDay ? `${payrollDay}. i måneden` : "Ikke satt"}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">Tema</span>
          <Badge variant="secondary">{themeLabels[theme] || theme}</Badge>
        </div>
      </div>

      <Separator />

      <Button onClick={onComplete} className="w-full" disabled={isSubmitting}>
        {isSubmitting ? "Lagrer..." : "Gå til hjem"}
      </Button>
    </div>
  );
}
