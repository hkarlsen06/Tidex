'use client';

import { useState, useEffect, useRef } from 'react';
import { Card } from '@/components/app/Card';
import { Label } from '@/components/app/Label';
import { Switch } from '@/components/app/Switch';
import { Separator } from '@/components/app/Separator';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/app/Tooltip';
import { updatePreferencesSettings } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface PreferencesFormProps {
  initialData: {
    directTimeInput: boolean;
    fullMinuteRange: boolean;
  };
  t: Dictionary;
}

export function PreferencesForm({ initialData, t }: PreferencesFormProps) {
  const router = useRouter();
  const isInitialMount = useRef(true);
  const [directTimeInput, setDirectTimeInput] = useState(initialData.directTimeInput);
  const [fullMinuteRange, setFullMinuteRange] = useState(initialData.fullMinuteRange);
  const [isSaving, setIsSaving] = useState(false);

  // Auto-save when preferences change
  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }

    const savePreferences = async () => {
      setIsSaving(true);
      try {
        await updatePreferencesSettings({
          direct_time_input: directTimeInput,
          full_minute_range: fullMinuteRange,
        });
        router.refresh();
      } catch (error) {
        console.error('Failed to save preferences:', error);
      } finally {
        setIsSaving(false);
      }
    };

    savePreferences();
  }, [directTimeInput, fullMinuteRange, router]);

  return (
    <div className="space-y-6">
      <Card className="p-6">
        <div className="space-y-6">
          <div className="space-y-4">
            <TooltipProvider>
              <div className="flex items-center justify-between">
                <div className="space-y-0.5 flex-1">
                  <div className="flex items-center gap-2">
                    <Label htmlFor="directTime" className="text-base font-medium cursor-pointer">
                      {t.pages.settings.preferences.directTimeEntry.label}
                    </Label>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <span className="text-text-secondary cursor-help">ⓘ</span>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>{t.pages.settings.preferences.directTimeEntry.tooltip}</p>
                      </TooltipContent>
                    </Tooltip>
                  </div>
                  <p className="text-sm text-text-secondary">
                    {t.pages.settings.preferences.directTimeEntry.description}
                  </p>
                </div>
                <Switch
                  id="directTime"
                  checked={directTimeInput}
                  onCheckedChange={setDirectTimeInput}
                  disabled={isSaving}
                />
              </div>

              <Separator />

              <div className="flex items-center justify-between">
                <div className="space-y-0.5 flex-1">
                  <div className="flex items-center gap-2">
                    <Label htmlFor="fullMinute" className="text-base font-medium cursor-pointer">
                      {t.pages.settings.preferences.fullMinuteRange.label}
                    </Label>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <span className="text-text-secondary cursor-help">ⓘ</span>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>{t.pages.settings.preferences.fullMinuteRange.tooltip}</p>
                      </TooltipContent>
                    </Tooltip>
                  </div>
                  <p className="text-sm text-text-secondary">
                    {t.pages.settings.preferences.fullMinuteRange.description}
                  </p>
                </div>
                <Switch
                  id="fullMinute"
                  checked={fullMinuteRange}
                  onCheckedChange={setFullMinuteRange}
                  disabled={isSaving}
                />
              </div>
            </TooltipProvider>
          </div>
        </div>
      </Card>
    </div>
  );
}
