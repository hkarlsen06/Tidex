'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Label } from '@appui/Label';
import { Button } from '@appui/Button';
import { RadioGroup, RadioGroupItem } from '@appui/RadioGroup';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@appui/Select';
import { updateDisplaySettings } from '../../_actions/updateSettings';
import { useRouter } from 'next/navigation';
import { useTheme } from 'next-themes';

interface DisplayFormProps {
  initialData: {
    theme: string;
    defaultShiftsView: string;
    currencyFormat: string;
  };
}

export function DisplayForm({ initialData }: DisplayFormProps) {
  const router = useRouter();
  const { setTheme } = useTheme();
  const [theme, setThemeState] = useState(initialData.theme);
  const [defaultShiftsView, setDefaultShiftsView] = useState(initialData.defaultShiftsView);
  const [currencyFormat, setCurrencyFormat] = useState(initialData.currencyFormat);
  const [isSaving, setIsSaving] = useState(false);

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await updateDisplaySettings({
        theme,
        default_shifts_view: defaultShiftsView,
        currency_format: currencyFormat,
      });

      // Apply theme immediately
      setTheme(theme);

      router.refresh();
      // You can add a toast notification here
    } catch (error) {
      console.error('Failed to save display settings:', error);
      // You can add error toast here
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="space-y-6">
      <Card className="p-6">
        <div className="space-y-6">
          <div className="space-y-4">
            <div>
              <Label className="text-base font-semibold">Tema</Label>
              <p className="text-sm text-text-secondary mb-4">
                Velg hvordan appen skal se ut
              </p>
              <RadioGroup value={theme} onValueChange={setThemeState}>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="light" id="light" />
                  <Label htmlFor="light" className="font-normal cursor-pointer">
                    Lys
                  </Label>
                </div>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="dark" id="dark" />
                  <Label htmlFor="dark" className="font-normal cursor-pointer">
                    Mørk
                  </Label>
                </div>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="system" id="system" />
                  <Label htmlFor="system" className="font-normal cursor-pointer">
                    System (automatisk)
                  </Label>
                </div>
              </RadioGroup>
            </div>
          </div>
        </div>
      </Card>

      <Card className="p-6">
        <div className="space-y-6">
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="defaultView" className="text-base font-semibold">
                Standard vaktoversikt
              </Label>
              <p className="text-sm text-text-secondary">
                Velg hvordan vakter vises som standard
              </p>
              <Select value={defaultShiftsView} onValueChange={setDefaultShiftsView}>
                <SelectTrigger id="defaultView">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="list">Liste</SelectItem>
                  <SelectItem value="calendar">Kalender</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="currency" className="text-base font-semibold">
                Valuta
              </Label>
              <p className="text-sm text-text-secondary">
                Velg hvordan beløp vises
              </p>
              <Select value={currencyFormat} onValueChange={setCurrencyFormat}>
                <SelectTrigger id="currency">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="NOK">NOK (kr)</SelectItem>
                  <SelectItem value="USD">USD ($)</SelectItem>
                  <SelectItem value="EUR">EUR (€)</SelectItem>
                  <SelectItem value="GBP">GBP (£)</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        </div>
      </Card>

      <div className="flex justify-end">
        <Button onClick={handleSave} disabled={isSaving}>
          {isSaving ? 'Lagrer...' : 'Lagre endringer'}
        </Button>
      </div>
    </div>
  );
}
