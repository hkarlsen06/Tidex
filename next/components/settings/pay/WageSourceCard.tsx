'use client';

import React from 'react';
import { Card } from '@/components/app/Card';
import { Label } from '@/components/app/Label';
import { Input } from '@/components/app/Input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/app/Select';
import { Separator } from '@/components/app/Separator';
import { Building, SlidersHorizontal, Calendar, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { TariffVersion } from '@/data-access/tariff';

interface WageSourceCardProps {
  usePreset: boolean;
  setUsePreset: (value: boolean) => void;
  wageLevel: string;
  setWageLevel: (value: string) => void;
  customWage: string;
  setCustomWage: (value: string) => void;
  disabled?: boolean;
  showCurrentWage?: boolean;
  /**
   * Optional tariff version for version-specific rates.
   * When provided, rates are taken from the version instead of PRESET_WAGE_RATES.
   */
  tariffVersion?: TariffVersion | null;
  labels?: {
    title?: string;
    description?: string;
    tariffButton?: string;
    customButton?: string;
    wageLevelLabel?: string;
    customWageLabel?: string;
    currentWageLabel?: string;
    wageLevelPrefix?: string;
    wageLevelUnder16?: string;
    wageLevel16to18?: string;
    perHour?: string;
    tariffVersionLabel?: string;
  };
}

export function WageSourceCard({
  usePreset,
  setUsePreset,
  wageLevel,
  setWageLevel,
  customWage,
  setCustomWage,
  disabled = false,
  showCurrentWage = true,
  tariffVersion,
  labels = {},
}: WageSourceCardProps) {
  // Tariff version is required for preset mode to show accurate rates
  const isLoadingTariff = usePreset && !tariffVersion;
  const wageRates = tariffVersion?.rates ?? {};

  const customWageValue = parseFloat(customWage);
  const isCustomWageInvalid =
    !usePreset &&
    (!customWage || Number.isNaN(customWageValue) || customWageValue < 1 || customWageValue > 10000);

  const getCurrentWage = () => {
    if (usePreset) {
      if (!tariffVersion) return '...';
      const rate = wageRates[wageLevel];
      return `${rate?.toFixed(2) || '0'} ${labels.perHour || 'kr/time'}`;
    }
    return `${customWage} ${labels.perHour || 'kr/time'}`;
  };

  return (
    <Card className="p-6">
      <div className="space-y-6">
        {(labels.title || labels.description) && (
          <>
            <div>
              {labels.title && <h3 className="text-lg font-semibold">{labels.title}</h3>}
              {labels.description && (
                <p className="text-sm text-text-secondary mt-1">{labels.description}</p>
              )}
            </div>
            <Separator />
          </>
        )}

        <div className="flex gap-4">
          <button
            type="button"
            onClick={() => !disabled && setUsePreset(true)}
            disabled={disabled}
            className={cn(
              'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
              'border-2',
              usePreset
                ? 'border-text-primary bg-surface-secondary'
                : 'border-border hover:border-border-subtle hover:bg-surface-primary',
              disabled && 'opacity-50 cursor-not-allowed'
            )}
          >
            <Building strokeWidth={2} className="h-8 w-8" />
            <span className="text-xs font-medium">{labels.tariffButton || 'Tariff'}</span>
          </button>

          <button
            type="button"
            onClick={() => !disabled && setUsePreset(false)}
            disabled={disabled}
            className={cn(
              'flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
              'border-2',
              !usePreset
                ? 'border-text-primary bg-surface-secondary'
                : 'border-border hover:border-border-subtle hover:bg-surface-primary',
              disabled && 'opacity-50 cursor-not-allowed'
            )}
          >
            <SlidersHorizontal strokeWidth={2} className="h-8 w-8" />
            <span className="text-xs font-medium">{labels.customButton || 'Egendefinert'}</span>
          </button>
        </div>

        {usePreset ? (
          <div className="space-y-2">
            <Label htmlFor="wageLevel">{labels.wageLevelLabel || 'Tariffsteg'}</Label>
            {isLoadingTariff ? (
              <div className="flex items-center justify-center h-10 rounded-md border border-border bg-surface-secondary">
                <Loader2 className="h-4 w-4 animate-spin text-text-muted" />
              </div>
            ) : (
              <Select value={wageLevel} onValueChange={setWageLevel} disabled={disabled}>
                <SelectTrigger id="wageLevel">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.keys(wageRates).map((level) => {
                    const levelNum = parseInt(level);
                    let label = `${labels.wageLevelPrefix || 'Steg'} ${level}`;

                    if (levelNum === -1) {
                      label = labels.wageLevelUnder16 || 'Under 16 år';
                    } else if (levelNum === -2) {
                      label = labels.wageLevel16to18 || '16-18 år';
                    }

                    return (
                      <SelectItem key={level} value={level}>
                        {label} - {wageRates[level].toFixed(2)} {labels.perHour || 'kr/time'}
                      </SelectItem>
                    );
                  })}
                </SelectContent>
              </Select>
            )}
            {/* Show tariff version info when available */}
            {tariffVersion && (
              <div className="flex items-center gap-1 text-xs text-text-muted">
                <Calendar className="h-3 w-3" />
                <span>
                  {labels.tariffVersionLabel || 'Tariff fra'}{' '}
                  {new Date(tariffVersion.effective_date + 'T00:00:00').toLocaleDateString('no-NO', {
                    year: 'numeric',
                    month: 'long',
                  })}
                </span>
              </div>
            )}
          </div>
        ) : (
          <div className="space-y-2">
            <Label htmlFor="customWage">{labels.customWageLabel || 'Egendefinert timelønn (kr)'}</Label>
            <Input
              id="customWage"
              type="number"
              min={1}
              max={10000}
              step={0.01}
              invalid={isCustomWageInvalid}
              value={customWage}
              onChange={(e) => setCustomWage(e.target.value)}
              disabled={disabled}
            />
            {isCustomWageInvalid && (
              <p className="text-sm text-destructive">Ugyldig timelønn (1-10000 kr)</p>
            )}
          </div>
        )}

        {showCurrentWage && (
          <div className="p-4 bg-surface-primary rounded-lg">
            <p className="text-sm text-text-secondary">{labels.currentWageLabel || 'Nåværende timelønn'}</p>
            <p className="text-xl font-semibold mt-1">{getCurrentWage()}</p>
          </div>
        )}
      </div>
    </Card>
  );
}
