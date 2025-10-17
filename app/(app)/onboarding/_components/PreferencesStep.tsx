"use client";

import { Label } from "@appui/Label";
import { Input } from "@appui/Input";
import { Button } from "@appui/Button";
import { Separator } from "@appui/Separator";
import { IconListDetails, IconCalendarWeek, IconSun, IconMoon, IconScreenShare } from '@tabler/icons-react';
import { cn } from '@/lib/utils';

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
          <Label className="text-base font-semibold">Velg tema</Label>
          <p className="text-sm text-text-secondary mb-4">
            Velg hvordan appen skal se ut
          </p>
          <div className="flex gap-2 sm:gap-4">
            <button
              type="button"
              onClick={() => setTheme('light')}
              className={cn(
                'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 transition-all',
                'border-2',
                theme === 'light'
                  ? 'border-text-primary bg-surface-secondary'
                  : 'border-border hover:border-border-subtle hover:bg-surface-primary'
              )}
            >
              <IconSun stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">Lys</span>
            </button>

            <button
              type="button"
              onClick={() => setTheme('dark')}
              className={cn(
                'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 transition-all',
                'border-2',
                theme === 'dark'
                  ? 'border-text-primary bg-surface-secondary'
                  : 'border-border hover:border-border-subtle hover:bg-surface-primary'
              )}
            >
              <IconMoon stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">Mørk</span>
            </button>

            <button
              type="button"
              onClick={() => setTheme('system')}
              className={cn(
                'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 transition-all',
                'border-2',
                theme === 'system'
                  ? 'border-text-primary bg-surface-secondary'
                  : 'border-border hover:border-border-subtle hover:bg-surface-primary'
              )}
            >
              <IconScreenShare stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">System</span>
            </button>
          </div>
        </div>

        <Separator />

        <div className="space-y-3">
          <Label className="text-base font-semibold">Standard vaktoversikt</Label>
          <p className="text-sm text-text-secondary mb-4">
            Velg hvordan vakter vises som standard
          </p>
          <div className="flex gap-2 sm:gap-4">
            <button
              type="button"
              onClick={() => setShiftsView('calendar')}
              className={cn(
                'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 transition-all',
                'border-2',
                shiftsView === 'calendar'
                  ? 'border-text-primary bg-surface-secondary'
                  : 'border-border hover:border-border-subtle hover:bg-surface-primary'
              )}
            >
              <IconCalendarWeek stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">Kalender</span>
            </button>

            <button
              type="button"
              onClick={() => setShiftsView('list')}
              className={cn(
                'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 transition-all',
                'border-2',
                shiftsView === 'list'
                  ? 'border-text-primary bg-surface-secondary'
                  : 'border-border hover:border-border-subtle hover:bg-surface-primary'
              )}
            >
              <IconListDetails stroke={2} className="h-8 w-8" />
              <span className="text-xs font-medium">Liste</span>
            </button>
          </div>
        </div>

        <Separator />

        <div className="space-y-2">
          <Label htmlFor="monthly-goal">Sett deg et månedlig lønnsmål</Label>
          <p className="text-sm text-text-muted">
            Dette brukes til å vise progresjon
          </p>
          <div className="relative">
            <Input
              id="monthly-goal"
              type="number"
              min={100}
              step={1000}
              value={monthlyGoal}
              onChange={(e) => setMonthlyGoal(e.target.value)}
              placeholder="10000"
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
