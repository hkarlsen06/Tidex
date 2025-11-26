"use client";

import { MutableRefObject, useRef, useState } from "react";
import { Label } from "@/components/app/Label";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@/components/app/Select";
import { Input } from "@/components/app/Input";
import { Button } from "@/components/app/Button";
import { PRESET_WAGE_RATES } from "@/lib/payroll/calc";
import { Building, SlidersHorizontal, ArrowDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { useTranslations } from "@/lib/i18n/client";
import { CURRENCY_GROUPS, getCurrencyConfig } from "@/lib/currency/currencies";

interface ArrowButtonConfig {
  available: boolean;
  activated: boolean;
  pressed: boolean;
}

const arrowButtonClasses = ({ available, activated, pressed }: ArrowButtonConfig) =>
  cn(
    "flex h-9 w-9 items-center justify-center rounded-md border border-border transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background touch-manipulation",
    available
      ? activated
        ? "cursor-default bg-surface-secondary text-text-secondary opacity-70"
        : "cursor-pointer bg-black text-white shadow-xs hover:opacity-90 dark:bg-white dark:text-black"
      : "cursor-not-allowed bg-surface-secondary text-text-muted opacity-40",
    pressed && "opacity-70"
  );

const triggerPressFeedback = (
  setPressed: (value: boolean) => void,
  timeoutRef: MutableRefObject<ReturnType<typeof setTimeout> | null>
) => {
  setPressed(true);
  if (timeoutRef.current) {
    clearTimeout(timeoutRef.current);
  }
  timeoutRef.current = setTimeout(() => {
    setPressed(false);
  }, 400);
};

interface WageStepProps {
  wageType: "preset" | "custom";
  setWageType: (value: "preset" | "custom") => void;
  wageLevel: string;
  setWageLevel: (value: string) => void;
  customWage: string;
  setCustomWage: (value: string) => void;
  currency: string;
  setCurrency: (value: string) => void;
  onNext: () => void;
}

export function WageStep({
  wageType,
  setWageType,
  wageLevel,
  setWageLevel,
  customWage,
  setCustomWage,
  currency,
  setCurrency,
  onNext,
}: WageStepProps) {
  const { t } = useTranslations();
  const wageValue = parseFloat(customWage);
  const currencyConfig = getCurrencyConfig(currency);

  // Track if currency has been confirmed (either by clicking arrow or changing value)
  const [currencyActivated, setCurrencyActivated] = useState(false);
  const [currencyButtonPressed, setCurrencyButtonPressed] = useState(false);
  const currencyButtonTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleCurrencyButtonPress = () => {
    setCurrencyActivated(true);
    triggerPressFeedback(setCurrencyButtonPressed, currencyButtonTimeout);
  };

  const isCustomWageInvalid =
    wageType === "custom" &&
    currencyActivated &&
    (!customWage || Number.isNaN(wageValue) || wageValue < 1 || wageValue > 10000);

  const handleNext = () => {
    if (wageType === "custom") {
      // Must have currency confirmed
      if (!currencyActivated) {
        return;
      }
      // Must have valid wage
      if (isCustomWageInvalid) {
        return;
      }
    }
    if (wageType === "preset" && !wageLevel) {
      return;
    }
    onNext();
  };

  // Check if form is complete for enabling Next button
  const isFormComplete =
    wageType === "preset"
      ? !!wageLevel
      : currencyActivated && !isCustomWageInvalid && !!customWage;

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
          <div className="space-y-4">
            {/* Currency selector */}
            <div className="space-y-2">
              <Label htmlFor="currency">{t.onboarding.wageStep.selectCurrency}</Label>
              <div className="flex items-stretch gap-2">
                <Select
                  value={currency}
                  onValueChange={(value) => {
                    setCurrency(value);
                    setCurrencyActivated(true);
                    triggerPressFeedback(setCurrencyButtonPressed, currencyButtonTimeout);
                  }}
                >
                  <SelectTrigger id="currency" className="flex-1">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {CURRENCY_GROUPS.map((group) => (
                      <SelectGroup key={group.label}>
                        <SelectLabel>{group.label}</SelectLabel>
                        {group.options.map((option) => (
                          <SelectItem key={option.value} value={option.value}>
                            {option.label}
                          </SelectItem>
                        ))}
                      </SelectGroup>
                    ))}
                  </SelectContent>
                </Select>
                <button
                  type="button"
                  onClick={handleCurrencyButtonPress}
                  aria-label={t.onboarding.wageStep.confirmCurrency}
                  className={arrowButtonClasses({
                    available: true,
                    activated: currencyActivated,
                    pressed: currencyButtonPressed,
                  })}
                >
                  <ArrowDown strokeWidth={2} className="h-4 w-4" />
                </button>
              </div>
            </div>

            {/* Hourly wage input - only enabled after currency confirmed */}
            <div className="space-y-2">
              <Label
                htmlFor="custom-wage"
                className={!currencyActivated ? "opacity-40" : ""}
              >
                {t.onboarding.wageStep.hourlyWage}
              </Label>
              <div className="relative">
                <Input
                  id="custom-wage"
                  type="number"
                  min={1}
                  max={10000}
                  invalid={isCustomWageInvalid}
                  value={customWage}
                  onChange={(e) => setCustomWage(e.target.value)}
                  disabled={!currencyActivated}
                  className="pr-16"
                  placeholder="200"
                />
                <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                  {currencyConfig.display === "suffix"
                    ? `${currency}${t.onboarding.wageStep.perHour}`
                    : `${t.onboarding.wageStep.perHour}`}
                </span>
              </div>
            </div>
          </div>
        )}
      </div>

      <Button onClick={handleNext} className="w-full" disabled={!isFormComplete}>
        {t.common.next}
      </Button>
    </div>
  );
}
