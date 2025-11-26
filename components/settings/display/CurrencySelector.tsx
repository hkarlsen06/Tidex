'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Card } from '@/components/app/Card';
import { Label } from '@/components/app/Label';
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from '@/components/app/Select';
import { updateDisplaySettings } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { CURRENCY_GROUPS } from '@/lib/currency/currencies';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface CurrencySelectorProps {
  initialCurrency: string;
  t: Dictionary;
}

export function CurrencySelector({ initialCurrency, t }: CurrencySelectorProps) {
  const router = useRouter();
  const [currency, setCurrency] = useState(initialCurrency);
  const [isSaving, setIsSaving] = useState(false);

  const handleCurrencyChange = async (newCurrency: string) => {
    setCurrency(newCurrency);
    setIsSaving(true);

    try {
      await updateDisplaySettings({ currency: newCurrency });
      router.refresh();
    } catch (error) {
      console.error('Failed to save currency:', error);
      // Revert on error
      setCurrency(initialCurrency);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Card className="p-6">
      <div className="space-y-4">
        <div>
          <Label className="text-base font-semibold">
            {t.pages.settings.display.currency.label}
          </Label>
          <p className="text-sm text-text-secondary mb-4">
            {t.pages.settings.display.currency.description}
          </p>
          <Select
            value={currency}
            onValueChange={handleCurrencyChange}
            disabled={isSaving}
          >
            <SelectTrigger className="w-full max-w-xs">
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
        </div>
      </div>
    </Card>
  );
}
