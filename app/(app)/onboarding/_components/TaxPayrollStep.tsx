"use client";

import { Label } from "@appui/Label";
import { Switch } from "@appui/Switch";
import { Input } from "@appui/Input";
import { Button } from "@appui/Button";
import { Separator } from "@appui/Separator";
import { InfoIcon } from "lucide-react";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@appui/Tooltip";

interface TaxPayrollStepProps {
  taxDeductionEnabled: boolean;
  setTaxDeductionEnabled: (value: boolean) => void;
  taxPercentage: string;
  setTaxPercentage: (value: string) => void;
  payrollDay: string;
  setPayrollDay: (value: string) => void;
  onNext: () => void;
  onBack: () => void;
}

export function TaxPayrollStep({
  taxDeductionEnabled,
  setTaxDeductionEnabled,
  taxPercentage,
  setTaxPercentage,
  payrollDay,
  setPayrollDay,
  onNext,
  onBack,
}: TaxPayrollStepProps) {
  const handleSkip = () => {
    setTaxDeductionEnabled(false);
    setPayrollDay("");
    onNext();
  };

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">Skattetrekk og lønningsdag</h2>
        <p className="text-text-secondary">
          Få et mer nøyaktig bilde av din nettoinntekt (valgfritt)
        </p>
      </div>

      <div className="space-y-6">
        {/* Tax Deduction Section */}
        <div className="space-y-4">
          <div className="flex items-center justify-between space-x-2">
            <div className="space-y-0.5 flex-1">
              <div className="flex items-center gap-2">
                <Label htmlFor="tax-enabled">Beregn skattetrekk</Label>
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <InfoIcon className="h-4 w-4 text-text-muted cursor-help" />
                    </TooltipTrigger>
                    <TooltipContent className="max-w-xs">
                      <p>
                        Når aktivert vil appen beregne estimert nettoinntekt
                        basert på din skatteprosent. Dette gir en mer realistisk
                        oversikt over din faktiske inntekt.
                      </p>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              </div>
              <p className="text-sm text-text-muted">
                Vis estimert nettoinntekt etter skatt
              </p>
            </div>
            <Switch
              id="tax-enabled"
              checked={taxDeductionEnabled}
              onCheckedChange={setTaxDeductionEnabled}
            />
          </div>

          {taxDeductionEnabled && (
            <div className="space-y-2 pl-4 border-l-2 border-border">
              <Label htmlFor="tax-percentage">Din skatteprosent</Label>
              <p className="text-sm text-text-muted">
                Gjennomsnittlig skattesats (finn denne på skatteetaten.no)
              </p>
              <div className="relative">
                <Input
                  id="tax-percentage"
                  type="number"
                  min={0}
                  max={100}
                  step={0.5}
                  value={taxPercentage}
                  onChange={(e) => setTaxPercentage(e.target.value)}
                  placeholder="30"
                  className="pr-12"
                />
                <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                  %
                </span>
              </div>
            </div>
          )}
        </div>

        <Separator />

        {/* Payroll Day Section */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Label htmlFor="payroll-day">Lønningsdag</Label>
            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <InfoIcon className="h-4 w-4 text-text-muted cursor-help" />
                </TooltipTrigger>
                <TooltipContent className="max-w-xs">
                  <p>
                    Hvilken dag i måneden får du utbetalt lønn? Dette brukes
                    til å vise "Dager til neste lønning" på dashbordet.
                  </p>
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>
          </div>
          <p className="text-sm text-text-muted">
            Hvilken dag i måneden får du lønn? (valgfritt)
          </p>
          <div className="relative">
            <Input
              id="payroll-day"
              type="number"
              min={1}
              max={31}
              value={payrollDay}
              onChange={(e) => setPayrollDay(e.target.value)}
              placeholder="15"
              className="pr-20"
            />
            <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
              dag i mnd
            </span>
          </div>
        </div>
      </div>

      {/* Check if any settings have been configured */}
      {(() => {
        const hasValidSettings =
          (taxDeductionEnabled && taxPercentage && parseFloat(taxPercentage) > 0) ||
          (payrollDay && parseInt(payrollDay) >= 1 && parseInt(payrollDay) <= 31);

        return (
          <div className="flex gap-3">
            <Button onClick={onBack} variant="outline" className="flex-1">
              Tilbake
            </Button>
            <Button
              onClick={handleSkip}
              variant="ghost"
              className="flex-1"
              disabled={!!hasValidSettings}
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
        );
      })()}
    </div>
  );
}
