"use client";

import { useState } from "react";
import { Label } from "@appui/Label";
import { Switch } from "@appui/Switch";
import { Input } from "@appui/Input";
import { Button } from "@appui/Button";
import { Separator } from "@appui/Separator";
import { InfoIcon } from "lucide-react";
import { Tooltip, TooltipContent, TooltipTrigger } from "@appui/Tooltip";
import { useTranslations } from "@/lib/i18n/client";

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
  const { t } = useTranslations();
  const [taxTooltipOpen, setTaxTooltipOpen] = useState(false);
  const [payrollTooltipOpen, setPayrollTooltipOpen] = useState(false);
  const payrollDayPresets = ["10", "15", "20"];
  const taxPercentagePresets = ["25", "30", "40"];

  const handleSkip = () => {
    setTaxDeductionEnabled(false);
    setPayrollDay("");
    onNext();
  };

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">{t.onboarding.taxPayrollStep.title}</h2>
        <p className="text-text-secondary">
          {t.onboarding.taxPayrollStep.description}
        </p>
      </div>

      <div className="space-y-6">
        {/* Payroll Day Section */}
          <div className="space-y-2">
            <div className="flex items-center gap-2">
              <Label htmlFor="payroll-day">{t.onboarding.taxPayrollStep.payrollDayLabel}</Label>
            <Tooltip open={payrollTooltipOpen} onOpenChange={setPayrollTooltipOpen} delayDuration={0}>
              <TooltipTrigger
                asChild
                onPointerDown={(e) => e.preventDefault()}
              >
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    setPayrollTooltipOpen(!payrollTooltipOpen);
                  }}
                  className="touch-manipulation"
                >
                  <InfoIcon className="h-4 w-4 text-text-muted cursor-pointer hover:text-text-primary transition-colors" />
                </button>
              </TooltipTrigger>
              <TooltipContent
                className="max-w-xs bg-surface-primary border-border text-text-primary"
                onPointerDownOutside={() => setPayrollTooltipOpen(false)}
                onEscapeKeyDown={() => setPayrollTooltipOpen(false)}
              >
                <p>
                  {t.onboarding.taxPayrollStep.payrollDayTooltip}
                </p>
              </TooltipContent>
            </Tooltip>
          </div>
          <p className="text-sm text-text-muted">
            {t.onboarding.taxPayrollStep.payrollDayDescription}
          </p>
          <div className="relative">
            <Input
              id="payroll-day"
              type="text"
              inputMode="numeric"
              pattern="[0-9]*"
              value={payrollDay}
              onChange={(e) => {
                const value = e.target.value;
                // Only allow empty string or integers
                if (value === '' || /^\d+$/.test(value)) {
                  setPayrollDay(value);
                }
              }}
              onKeyDown={(e) => {
                // Prevent decimal point and comma
                if (e.key === '.' || e.key === ',') {
                  e.preventDefault();
                }
              }}
              placeholder="15"
              className="pr-20"
            />
            <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
              {t.onboarding.taxPayrollStep.dayInMonth}
            </span>
          </div>
          <div className="grid grid-cols-3 gap-2">
            {payrollDayPresets.map((value) => (
              <Button
                key={value}
                type="button"
                variant={payrollDay === value ? "default" : "outline"}
                className="w-full"
                onClick={() => setPayrollDay(value)}
              >
                {value}. {t.onboarding.taxPayrollStep.day}
              </Button>
            ))}
          </div>
        </div>

        <Separator />

        {/* Tax Deduction Section */}
        <div className="space-y-4">
          <div className="flex items-center justify-between space-x-2">
            <div className="space-y-0.5 flex-1">
              <div className="flex items-center gap-2">
                <Label htmlFor="tax-enabled">{t.onboarding.taxPayrollStep.calculateTax}</Label>
                <Tooltip open={taxTooltipOpen} onOpenChange={setTaxTooltipOpen} delayDuration={0}>
                  <TooltipTrigger
                    asChild
                    onPointerDown={(e) => e.preventDefault()}
                  >
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        setTaxTooltipOpen(!taxTooltipOpen);
                      }}
                      className="touch-manipulation"
                    >
                      <InfoIcon className="h-4 w-4 text-text-muted cursor-pointer hover:text-text-primary transition-colors" />
                    </button>
                  </TooltipTrigger>
                  <TooltipContent
                    className="max-w-xs bg-surface-primary border-border text-text-primary"
                    onPointerDownOutside={() => setTaxTooltipOpen(false)}
                    onEscapeKeyDown={() => setTaxTooltipOpen(false)}
                  >
                    <p>
                      {t.onboarding.taxPayrollStep.taxTooltip}
                    </p>
                  </TooltipContent>
                </Tooltip>
              </div>
              <p className="text-sm text-text-muted">
                {t.onboarding.taxPayrollStep.taxDescription}
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
              <Label htmlFor="tax-percentage">{t.onboarding.taxPayrollStep.taxPercentageLabel}</Label>
              <p className="text-sm text-text-muted">
                {t.onboarding.taxPayrollStep.taxPercentageDescription}
              </p>
              <div className="relative">
                <Input
                  id="tax-percentage"
                  type="number"
                  min={0}
                  max={100}
                  value={taxPercentage}
                  onChange={(e) => setTaxPercentage(e.target.value)}
                  placeholder="30"
                  className="pr-12"
                />
                <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                  %
                </span>
              </div>
              <div className="grid grid-cols-3 gap-2">
                {taxPercentagePresets.map((value) => (
                  <Button
                    key={value}
                    type="button"
                    variant={taxPercentage === value ? "default" : "outline"}
                    className="w-full"
                    onClick={() => setTaxPercentage(value)}
                  >
                    {value}%
                  </Button>
                ))}
              </div>
            </div>
          )}
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
              {t.common.back}
            </Button>
            <Button
              onClick={handleSkip}
              variant="ghost"
              className="flex-1"
              disabled={!!hasValidSettings}
            >
              {t.onboarding.taxPayrollStep.skip}
            </Button>
            <Button
              onClick={onNext}
              className="flex-1"
              disabled={!hasValidSettings}
            >
              {t.common.next}
            </Button>
          </div>
        );
      })()}
    </div>
  );
}
