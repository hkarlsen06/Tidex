"use client";

import { Label } from "@/components/app/Label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/app/Select";
import { Input } from "@/components/app/Input";
import { Button } from "@/components/app/Button";
import { PRESET_WAGE_RATES } from "@/lib/payroll/calc";
import { Building, SlidersHorizontal } from "lucide-react";
import { cn } from "@/lib/utils";
import { useTranslations } from "@/lib/i18n/client";

interface WageStepProps {
  wageType: "preset" | "custom";
  setWageType: (value: "preset" | "custom") => void;
  wageLevel: string;
  setWageLevel: (value: string) => void;
  customWage: string;
  setCustomWage: (value: string) => void;
  onNext: () => void;
}

export function WageStep({
  wageType,
  setWageType,
  wageLevel,
  setWageLevel,
  customWage,
  setCustomWage,
  onNext,
}: WageStepProps) {
  const { t } = useTranslations();
  const wageValue = parseFloat(customWage);
  const isCustomWageInvalid =
    wageType === "custom" &&
    (!customWage || Number.isNaN(wageValue) || wageValue < 1 || wageValue > 10000);

  const handleNext = () => {
    if (isCustomWageInvalid) {
      return;
    }
    if (wageType === "preset" && !wageLevel) {
      return;
    }
    onNext();
  };

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">{t.onboarding.wageStep.title}</h2>
        <p className="text-text-secondary">{t.onboarding.wageStep.description}</p>
      </div>

      <div className="space-y-6">
        <div className="space-y-2">
          <div className="flex gap-2 sm:gap-4">
            <button
              type="button"
              onClick={() => setWageType("preset")}
              className={cn(
                "flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 transition-all",
                "border-2",
                wageType === "preset"
                  ? "border-text-primary bg-surface-secondary"
                  : "border-border hover:border-border-subtle hover:bg-surface-primary"
              )}
            >
              <Building strokeWidth={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.onboarding.wageStep.preset}</span>
            </button>

            <button
              type="button"
              onClick={() => setWageType("custom")}
              className={cn(
                "flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 transition-all",
                "border-2",
                wageType === "custom"
                  ? "border-text-primary bg-surface-secondary"
                  : "border-border hover:border-border-subtle hover:bg-surface-primary"
              )}
            >
              <SlidersHorizontal strokeWidth={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.onboarding.wageStep.custom}</span>
            </button>
          </div>
        </div>

        {wageType === "preset" && (
          <div className="space-y-2">
            <Label htmlFor="wage-level">{t.onboarding.wageStep.selectPresetLevel}</Label>
            <Select value={wageLevel} onValueChange={setWageLevel}>
              <SelectTrigger id="wage-level">
                <SelectValue placeholder={t.onboarding.wageStep.selectLevelPlaceholder} />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(PRESET_WAGE_RATES).map(([level, rate]) => {
                  return (
                    <SelectItem key={level} value={level}>
                      {t.onboarding.wageStep.wageLevels[level as keyof typeof t.onboarding.wageStep.wageLevels]} - {rate.toFixed(2)} kr/t
                    </SelectItem>
                  );
                })}
              </SelectContent>
            </Select>
          </div>
        )}

        {wageType === "custom" && (
          <div className="space-y-2">
            <Label htmlFor="custom-wage">{t.onboarding.wageStep.hourlyWage}</Label>
            <div className="relative">
              <Input
                id="custom-wage"
                type="number"
                min={1}
                max={10000}
                invalid={isCustomWageInvalid}
                value={customWage}
                onChange={(e) => setCustomWage(e.target.value)}
                className="pr-12"
                placeholder="200"
              />
              <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                {t.onboarding.wageStep.perHour}
              </span>
            </div>
          </div>
        )}
      </div>

      <Button onClick={handleNext} className="w-full">
        {t.common.next}
      </Button>
    </div>
  );
}
