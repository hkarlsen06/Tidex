'use client';

import { useState, useEffect, useRef } from 'react';
import { Card } from '@appui/Card';
import { Label } from '@appui/Label';
import { Switch } from '@appui/Switch';
import { Separator } from '@appui/Separator';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@appui/Tooltip';
import { updatePreferencesSettings } from '@/app/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';

interface PreferencesFormProps {
  initialData: {
    directTimeInput: boolean;
    fullMinuteRange: boolean;
  };
}

export function PreferencesForm({ initialData }: PreferencesFormProps) {
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
                      Direkte tidsregistrering
                    </Label>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <span className="text-text-secondary cursor-help">ⓘ</span>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>Skriv inn tid direkte i stedet for å bruke tidvelger</p>
                      </TooltipContent>
                    </Tooltip>
                  </div>
                  <p className="text-sm text-text-secondary">
                    Skriv inn tidspunkt direkte som tekst
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
                      Fullt minuttområde
                    </Label>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <span className="text-text-secondary cursor-help">ⓘ</span>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>Tillat alle minutter (0-59) i stedet for 15-minutters intervaller</p>
                      </TooltipContent>
                    </Tooltip>
                  </div>
                  <p className="text-sm text-text-secondary">
                    Velg alle minutter i tidsvelgeren
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
