"use client";

import { Label } from "@appui/Label";
import { RadioGroup, RadioGroupItem } from "@appui/RadioGroup";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@appui/Select";
import { Input } from "@appui/Input";
import { Button } from "@appui/Button";
import { PRESET_WAGE_RATES } from "@/lib/payroll/calc";

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

      <div className="space-y-4">
        <div className="space-y-2">
          <RadioGroup value={wageType} onValueChange={(v) => setWageType(v as "preset" | "custom")}>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="preset" id="preset" />
              <Label htmlFor="preset">Jeg er på tariffavtale</Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="custom" id="custom" />
              <Label htmlFor="custom">Jeg har egendefinert lønn</Label>
            </div>
          </RadioGroup>
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
