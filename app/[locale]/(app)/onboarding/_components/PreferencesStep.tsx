"use client";

import { Label } from "@appui/Label";
import { Input } from "@appui/Input";
import { Button } from "@appui/Button";
import { Separator } from "@appui/Separator";
import { List, CalendarDays, Sun, Moon, ScreenShare } from 'lucide-react';
import { cn } from '@/lib/utils';
import { formatPlainAmount } from '@/lib/formatters';
import { useTranslations } from '@/lib/i18n/client';

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
  const { t } = useTranslations();
  const monthlyGoalPresets = ["15000", "20000", "25000"];

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">{t.onboarding.preferencesStep.title}</h2>
        <p className="text-text-secondary">{t.onboarding.preferencesStep.description}</p>
      </div>

      <div className="space-y-6">
        <div className="space-y-3">
          <Label className="text-base font-semibold">{t.onboarding.preferencesStep.selectTheme}</Label>
          <p className="text-sm text-text-secondary mb-4">
            {t.onboarding.preferencesStep.themeDescription}
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
              <Sun strokeWidth={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.onboarding.preferencesStep.themeLight}</span>
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
              <Moon strokeWidth={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.onboarding.preferencesStep.themeDark}</span>
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
              <ScreenShare strokeWidth={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.onboarding.preferencesStep.themeSystem}</span>
            </button>
          </div>
        </div>

        <Separator />

        <div className="space-y-3">
          <Label className="text-base font-semibold">{t.onboarding.preferencesStep.defaultView}</Label>
          <p className="text-sm text-text-secondary mb-4">
            {t.onboarding.preferencesStep.viewDescription}
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
              <CalendarDays strokeWidth={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.onboarding.preferencesStep.viewCalendar}</span>
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
              <List strokeWidth={2} className="h-8 w-8" />
              <span className="text-xs font-medium">{t.onboarding.preferencesStep.viewList}</span>
            </button>
          </div>
        </div>

        <Separator />

        <div className="space-y-2">
          <Label htmlFor="monthly-goal">{t.onboarding.preferencesStep.monthlyGoalLabel}</Label>
          <p className="text-sm text-text-muted">
            {t.onboarding.preferencesStep.monthlyGoalDescription}
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
              {t.onboarding.preferencesStep.currency}
            </span>
          </div>
          <div className="grid grid-cols-3 gap-2">
            {monthlyGoalPresets.map((value) => {
              const numericValue = Number(value);
              return (
                <Button
                  key={value}
                  type="button"
                  variant={monthlyGoal === value ? "default" : "outline"}
                  className="w-full"
                  onClick={() => setMonthlyGoal(value)}
                >
                  {formatPlainAmount(numericValue)} {t.onboarding.preferencesStep.currency}
                </Button>
              );
            })}
          </div>
        </div>
      </div>

      <div className="flex gap-3">
        <Button onClick={onBack} variant="outline" className="flex-1">
          {t.common.back}
        </Button>
        <Button onClick={onNext} className="flex-1">
          {t.common.next}
        </Button>
      </div>
    </div>
  );
}
