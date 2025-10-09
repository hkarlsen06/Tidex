'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Label } from '@appui/Label';
import { updateDisplaySettings } from '@/app/(app)/settings/_actions/updateSettings';
import { useRouter } from 'next/navigation';
import { IconListDetails, IconCalendarWeek, IconSun, IconMoon, IconScreenShare } from '@tabler/icons-react';
import { cn } from '@/lib/utils';

interface DisplayFormProps {
  initialData: {
    theme: string;
    defaultShiftsView: string;
  };
}

export function DisplayForm({ initialData }: DisplayFormProps) {
  const router = useRouter();
  const [theme, setTheme] = useState(initialData.theme || 'system');
  const [defaultShiftsView, setDefaultShiftsView] = useState(initialData.defaultShiftsView);
  const [isSaving, setIsSaving] = useState(false);

  const handleThemeChange = async (newTheme: string) => {
    setTheme(newTheme);
    setIsSaving(true);

    try {
      // Save to localStorage
      localStorage.setItem('theme', newTheme);

      // Apply theme immediately to DOM
      if (newTheme === 'system') {
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        document.documentElement.classList.toggle('dark', prefersDark);
      } else {
        document.documentElement.classList.toggle('dark', newTheme === 'dark');
      }

      await updateDisplaySettings({
        theme: newTheme,
        default_shifts_view: defaultShiftsView,
      });

      router.refresh();
    } catch (error) {
      console.error('Failed to save theme:', error);
    } finally {
      setIsSaving(false);
    }
  };

  const handleViewChange = async (newView: string) => {
    setDefaultShiftsView(newView);
    setIsSaving(true);

    try {
      await updateDisplaySettings({
        theme,
        default_shifts_view: newView,
      });

      router.refresh();
    } catch (error) {
      console.error('Failed to save view preference:', error);
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
              <div className="flex gap-4">
                <button
                  type="button"
                  onClick={() => handleThemeChange('light')}
                  disabled={isSaving}
                  className={cn(
                    'flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
                    'border-2',
                    theme === 'light'
                      ? 'border-text-primary bg-surface-secondary'
                      : 'border-border hover:border-border-subtle hover:bg-surface-primary',
                    isSaving && 'opacity-50 cursor-not-allowed'
                  )}
                >
                  <IconSun stroke={2} className="h-8 w-8" />
                  <span className="text-xs font-medium">Lys</span>
                </button>

                <button
                  type="button"
                  onClick={() => handleThemeChange('dark')}
                  disabled={isSaving}
                  className={cn(
                    'flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
                    'border-2',
                    theme === 'dark'
                      ? 'border-text-primary bg-surface-secondary'
                      : 'border-border hover:border-border-subtle hover:bg-surface-primary',
                    isSaving && 'opacity-50 cursor-not-allowed'
                  )}
                >
                  <IconMoon stroke={2} className="h-8 w-8" />
                  <span className="text-xs font-medium">Mørk</span>
                </button>

                <button
                  type="button"
                  onClick={() => handleThemeChange('system')}
                  disabled={isSaving}
                  className={cn(
                    'flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
                    'border-2',
                    theme === 'system'
                      ? 'border-text-primary bg-surface-secondary'
                      : 'border-border hover:border-border-subtle hover:bg-surface-primary',
                    isSaving && 'opacity-50 cursor-not-allowed'
                  )}
                >
                  <IconScreenShare stroke={2} className="h-8 w-8" />
                  <span className="text-xs font-medium">System</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </Card>

      <Card className="p-6">
        <div className="space-y-6">
          <div className="space-y-4">
            <div>
              <Label className="text-base font-semibold">Standard vaktoversikt</Label>
              <p className="text-sm text-text-secondary mb-4">
                Velg hvordan vakter vises som standard
              </p>
              <div className="flex gap-4">
                <button
                  type="button"
                  onClick={() => handleViewChange('list')}
                  disabled={isSaving}
                  className={cn(
                    'flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
                    'border-2',
                    defaultShiftsView === 'list'
                      ? 'border-text-primary bg-surface-secondary'
                      : 'border-border hover:border-border-subtle hover:bg-surface-primary',
                    isSaving && 'opacity-50 cursor-not-allowed'
                  )}
                >
                  <IconListDetails stroke={2} className="h-8 w-8" />
                  <span className="text-xs font-medium">Liste</span>
                </button>

                <button
                  type="button"
                  onClick={() => handleViewChange('calendar')}
                  disabled={isSaving}
                  className={cn(
                    'flex flex-col items-center justify-center gap-2 rounded-2xl px-8 py-6 transition-all',
                    'border-2',
                    defaultShiftsView === 'calendar'
                      ? 'border-text-primary bg-surface-secondary'
                      : 'border-border hover:border-border-subtle hover:bg-surface-primary',
                    isSaving && 'opacity-50 cursor-not-allowed'
                  )}
                >
                  <IconCalendarWeek stroke={2} className="h-8 w-8" />
                  <span className="text-xs font-medium">Kalender</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </Card>
    </div>
  );
}
