"use client";

import { Label } from "@appui/Label";
import { RadioGroup, RadioGroupItem } from "@appui/RadioGroup";
import { Input } from "@appui/Input";
import { Button } from "@appui/Button";
import { Separator } from "@appui/Separator";

interface PreferencesStepProps {
  theme: string;
  setTheme: (value: string) => void;
  shiftsView: string;
  setShiftsView: (value: string) => void;
  monthlyGoal: string;
  setMonthlyGoal: (value: string) => void;
  onNext: () => void;
  onBack: () => void;
}

export function PreferencesStep({
  theme,
  setTheme,
  shiftsView,
  setShiftsView,
  monthlyGoal,
  setMonthlyGoal,
  onNext,
  onBack,
}: PreferencesStepProps) {
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">Tilpass opplevelsen</h2>
        <p className="text-text-secondary">Velg tema og visning.</p>
      </div>

      <div className="space-y-6">
        <div className="space-y-3">
          <Label>Velg tema</Label>
          <RadioGroup value={theme} onValueChange={setTheme}>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="light" id="theme-light" />
              <Label htmlFor="theme-light">
                Lys
              </Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="dark" id="theme-dark" />
              <Label htmlFor="theme-dark">
                Mørk
              </Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="system" id="theme-system" />
              <Label htmlFor="theme-system">
                System
              </Label>
            </div>
          </RadioGroup>
        </div>

        <Separator />

        <div className="space-y-3">
          <Label>Foretrekker du liste eller kalendervisning?</Label>
          <RadioGroup value={shiftsView} onValueChange={setShiftsView}>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="list" id="view-list" />
              <Label htmlFor="view-list">Liste</Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="calendar" id="view-calendar" />
              <Label htmlFor="view-calendar">Kalender</Label>
            </div>
          </RadioGroup>
        </div>

        <Separator />

        <div className="space-y-2">
          <Label htmlFor="monthly-goal">Har du et månedlig lønnsmål?</Label>
          <p className="text-sm text-text-muted">
            Dette brukes til å vise progresjon på dashbordet
          </p>
          <div className="relative">
            <Input
              id="monthly-goal"
              type="number"
              min={0}
              step={1000}
              value={monthlyGoal}
              onChange={(e) => setMonthlyGoal(e.target.value)}
              placeholder="20000"
              className="pr-12"
            />
            <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
              kr
            </span>
          </div>
        </div>
      </div>

      <div className="flex gap-3">
        <Button onClick={onBack} variant="outline" className="flex-1">
          Tilbake
        </Button>
        <Button onClick={onNext} className="flex-1">
          Neste
        </Button>
      </div>
    </div>
  );
}
