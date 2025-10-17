"use client";

import { Label } from "@appui/Label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@appui/Select";
import { Input } from "@appui/Input";
import { Button } from "@appui/Button";
import { PRESET_WAGE_RATES } from "@/lib/payroll/calc";
import { IconBuilding, IconAdjustments } from "@tabler/icons-react";
import { cn } from "@/lib/utils";

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
  const handleNext = () => {
    if (wageType === "custom" && (!customWage || parseFloat(customWage) < 100)) {
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
        <h2 className="text-2xl font-bold">Hva er din timelønn?</h2>
        <p className="text-text-secondary">Vi trenger dette for å beregne lønnen din nøyaktig.</p>
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
              <IconBuilding stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">Tariff</span>
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
              <IconAdjustments stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">Egendefinert</span>
            </button>
          </div>
        </div>

        {wageType === "preset" && (
          <div className="space-y-2">
            <Label htmlFor="wage-level">Velg tariff nivå</Label>
            <Select value={wageLevel} onValueChange={setWageLevel}>
              <SelectTrigger id="wage-level">
                <SelectValue placeholder="Velg nivå" />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(PRESET_WAGE_RATES).map(([level, rate]) => {
                  const labels: Record<string, string> = {
                    "-2": "16 - 18 år",
                    "-1": "Under 16 år",
                    "1": "Lønnstrinn 1",
                    "2": "Lønnstrinn 2",
                    "3": "Lønnstrinn 3",
                    "4": "Lønnstrinn 4",
                    "5": "Lønnstrinn 5",
                    "6": "Lønnstrinn 6",
                  };
                  return (
                    <SelectItem key={level} value={level}>
                      {labels[level]} - {rate.toFixed(2)} kr/t
                    </SelectItem>
                  );
                })}
              </SelectContent>
            </Select>
          </div>
        )}

        {wageType === "custom" && (
          <div className="space-y-2">
            <Label htmlFor="custom-wage">Timelønn</Label>
            <div className="relative">
              <Input
                id="custom-wage"
                type="number"
                min={100}
                value={customWage}
                onChange={(e) => setCustomWage(e.target.value)}
                className="pr-12"
                placeholder="200"
              />
              <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                kr/t
              </span>
            </div>
          </div>
        )}
      </div>

      <Button onClick={handleNext} className="w-full">
        Neste
      </Button>
    </div>
  );
}
