'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Label } from '@appui/Label';
import { Button } from '@appui/Button';
import { Switch } from '@appui/Switch';
import { Separator } from '@appui/Separator';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@appui/Tooltip';
import { updatePreferencesSettings } from '../../_actions/updateSettings';
import { useRouter } from 'next/navigation';

interface PreferencesFormProps {
  initialData: {
    showEmployeeTab: boolean;
    directTimeInput: boolean;
    fullMinuteRange: boolean;
  };
}

export function PreferencesForm({ initialData }: PreferencesFormProps) {
  const router = useRouter();
  const [showEmployeeTab, setShowEmployeeTab] = useState(initialData.showEmployeeTab);
  const [directTimeInput, setDirectTimeInput] = useState(initialData.directTimeInput);
  const [fullMinuteRange, setFullMinuteRange] = useState(initialData.fullMinuteRange);
  const [isSaving, setIsSaving] = useState(false);

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await updatePreferencesSettings({
        show_employee_tab: showEmployeeTab,
        direct_time_input: directTimeInput,
        full_minute_range: fullMinuteRange,
      });
      router.refresh();
      // You can add a toast notification here
    } catch (error) {
      console.error('Failed to save preferences:', error);
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
            <TooltipProvider>
              <div className="flex items-center justify-between">
                <div className="space-y-0.5 flex-1">
                  <div className="flex items-center gap-2">
                    <Label htmlFor="employeeTab" className="text-base font-medium cursor-pointer">
                      Vis ansattfane
                    </Label>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <span className="text-text-secondary cursor-help">ⓘ</span>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>Viser en egen fane for ansattrelaterte funksjoner</p>
                      </TooltipContent>
                    </Tooltip>
                  </div>
                  <p className="text-sm text-text-secondary">
                    Aktiver ansattfunksjoner i navigasjonen
                  </p>
                </div>
                <Switch
                  id="employeeTab"
                  checked={showEmployeeTab}
                  onCheckedChange={setShowEmployeeTab}
                />
              </div>

              <Separator />

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
                />
              </div>
            </TooltipProvider>
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
