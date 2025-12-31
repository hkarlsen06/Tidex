'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { Card } from '@/components/app/Card';
import { Label } from '@/components/app/Label';
import { Switch } from '@/components/app/Switch';
import { Button } from '@/components/app/Button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/app/Select';
import {
  updateNotificationSettings,
  updateShiftReminderSettings,
  updateSummaryTime,
} from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { pushNotificationService } from '@/lib/notifications/push-service';
import { isNativePlatform } from '@/lib/capacitor/platform';
import { useRouter } from 'next/navigation';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { Plus, X } from 'lucide-react';

type PermissionStatus = 'granted' | 'denied' | 'prompt' | 'unknown';

interface NotificationSettingsFormProps {
  initialData: {
    sharedShiftsEnabled: boolean;
    shiftRemindersEnabled: boolean;
    shiftReminderMinutesArray: number[];
    summaryTime: string; // HH:MM:SS format from database
  };
  t: Dictionary;
}

// Available reminder options in minutes
const REMINDER_OPTIONS = [
  { value: 15, labelKey: 'min15' },
  { value: 30, labelKey: 'min30' },
  { value: 60, labelKey: 'hour1' },
  { value: 120, labelKey: 'hour2' },
  { value: 300, labelKey: 'hour5' },
  { value: 1440, labelKey: 'hour24' },
] as const;

const MAX_REMINDERS = 3;

// Time options for summary notifications (every hour)
const SUMMARY_TIME_OPTIONS = Array.from({ length: 24 }, (_, i) => {
  const hour = i.toString().padStart(2, '0');
  return { value: `${hour}:00`, label: `${hour}:00` };
});

export function NotificationSettingsForm({ initialData, t }: NotificationSettingsFormProps) {
  const router = useRouter();
  const isInitialMount = useRef(true);
  const isReminderInitialMount = useRef(true);
  const isSummaryTimeInitialMount = useRef(true);
  const [sharedShiftsEnabled, setSharedShiftsEnabled] = useState(initialData.sharedShiftsEnabled);
  const [shiftRemindersEnabled, setShiftRemindersEnabled] = useState(initialData.shiftRemindersEnabled);
  const [shiftReminderMinutesArray, setShiftReminderMinutesArray] = useState<number[]>(
    initialData.shiftReminderMinutesArray
  );
  // Convert HH:MM:SS to HH:MM for display
  const [summaryTime, setSummaryTime] = useState(() =>
    initialData.summaryTime.substring(0, 5)
  );
  const [isSaving, setIsSaving] = useState(false);
  const [permissionStatus, setPermissionStatus] = useState<PermissionStatus>('unknown');
  const [isNative, setIsNative] = useState(false);

  // Check platform and permission status on mount
  useEffect(() => {
    const checkPlatformAndPermission = async () => {
      const native = isNativePlatform();
      setIsNative(native);

      if (!native) {
        // On web, just show as granted (we don't do web push yet)
        setPermissionStatus('granted');
        return;
      }

      try {
        const { FirebaseMessaging } = await import('@capacitor-firebase/messaging');
        const status = await FirebaseMessaging.checkPermissions();
        setPermissionStatus(status.receive as PermissionStatus);
      } catch {
        setPermissionStatus('unknown');
      }
    };

    checkPlatformAndPermission();
  }, []);

  // Auto-save when preference changes
  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }

    const savePreferences = async () => {
      setIsSaving(true);
      try {
        await updateNotificationSettings({
          shared_shifts_enabled: sharedShiftsEnabled,
        });
        router.refresh();
      } catch (error) {
        console.error('Failed to save notification settings:', error);
      } finally {
        setIsSaving(false);
      }
    };

    savePreferences();
  }, [sharedShiftsEnabled, router]);

  // Auto-save when shift reminder preferences change
  useEffect(() => {
    if (isReminderInitialMount.current) {
      isReminderInitialMount.current = false;
      return;
    }

    const saveReminderPreferences = async () => {
      setIsSaving(true);
      try {
        await updateShiftReminderSettings({
          shift_reminders_enabled: shiftRemindersEnabled,
          shift_reminder_minutes_array: shiftReminderMinutesArray,
        });
        router.refresh();
      } catch (error) {
        console.error('Failed to save shift reminder settings:', error);
      } finally {
        setIsSaving(false);
      }
    };

    saveReminderPreferences();
  }, [shiftRemindersEnabled, shiftReminderMinutesArray, router]);

  // Auto-save when summary time changes
  useEffect(() => {
    if (isSummaryTimeInitialMount.current) {
      isSummaryTimeInitialMount.current = false;
      return;
    }

    const saveSummaryTime = async () => {
      setIsSaving(true);
      try {
        await updateSummaryTime(summaryTime);
        router.refresh();
      } catch (error) {
        console.error('Failed to save summary time:', error);
      } finally {
        setIsSaving(false);
      }
    };

    saveSummaryTime();
  }, [summaryTime, router]);

  const handleRequestPermission = useCallback(async () => {
    if (!isNative) return;

    try {
      const { FirebaseMessaging } = await import('@capacitor-firebase/messaging');
      const result = await FirebaseMessaging.requestPermissions();
      setPermissionStatus(result.receive as PermissionStatus);

      if (result.receive === 'granted') {
        // Re-initialize push service to register token
        await pushNotificationService.initialize();
      }
    } catch (error) {
      console.error('Failed to request permission:', error);
    }
  }, [isNative]);

  const handleAddReminder = useCallback(() => {
    if (shiftReminderMinutesArray.length >= MAX_REMINDERS) return;

    // Find the first available option that's not already selected
    const availableOption = REMINDER_OPTIONS.find(
      (opt) => !shiftReminderMinutesArray.includes(opt.value)
    );

    if (availableOption) {
      const newArray = [...shiftReminderMinutesArray, availableOption.value].sort((a, b) => b - a);
      setShiftReminderMinutesArray(newArray);
    }
  }, [shiftReminderMinutesArray]);

  const handleRemoveReminder = useCallback((index: number) => {
    if (shiftReminderMinutesArray.length <= 1) return;
    const newArray = shiftReminderMinutesArray.filter((_, i) => i !== index);
    setShiftReminderMinutesArray(newArray);
  }, [shiftReminderMinutesArray]);

  const handleChangeReminder = useCallback((index: number, value: number) => {
    const newArray = [...shiftReminderMinutesArray];
    newArray[index] = value;
    // Remove duplicates and sort descending
    const uniqueSorted = [...new Set(newArray)].sort((a, b) => b - a);
    setShiftReminderMinutesArray(uniqueSorted);
  }, [shiftReminderMinutesArray]);

  const getReminderLabel = (minutes: number): string => {
    const option = REMINDER_OPTIONS.find((opt) => opt.value === minutes);
    if (!option) return `${minutes} min`;

    const options = notifications.shiftReminders.options as Record<string, string>;
    return options[option.labelKey] || `${minutes} min`;
  };

  const getAvailableOptions = (currentValue: number) => {
    // Return all options, but the current one is always available
    return REMINDER_OPTIONS.filter(
      (opt) => opt.value === currentValue || !shiftReminderMinutesArray.includes(opt.value)
    );
  };

  const notifications = t.pages.settings.notifications;

  return (
    <div className="space-y-6">
      <Card className="p-6">
        <div className="space-y-6">
          {/* Permission denied warning */}
          {isNative && permissionStatus === 'denied' && (
            <div className="p-4 bg-amber-50 dark:bg-amber-950/20 text-amber-800 dark:text-amber-200 rounded-lg">
              <p className="text-sm">
                {notifications.permissionDenied}
              </p>
            </div>
          )}

          {/* Enable notifications button when permission is prompt */}
          {isNative && permissionStatus === 'prompt' && (
            <Button
              onClick={handleRequestPermission}
              className="w-full"
            >
              {notifications.enableButton}
            </Button>
          )}

          {/* Shared shifts toggle */}
          <div className="flex items-center justify-between">
            <div className="space-y-0.5 flex-1">
              <Label htmlFor="sharedShifts" className="text-base font-medium cursor-pointer">
                {notifications.sharedShifts.label}
              </Label>
              <p className="text-sm text-text-secondary">
                {notifications.sharedShifts.description}
              </p>
            </div>
            <Switch
              id="sharedShifts"
              checked={sharedShiftsEnabled}
              onCheckedChange={setSharedShiftsEnabled}
              disabled={isSaving || (isNative && permissionStatus === 'denied')}
            />
          </div>

          {/* Divider */}
          <div className="border-t border-border" />

          {/* Shift reminders toggle */}
          <div className="flex items-center justify-between">
            <div className="space-y-0.5 flex-1">
              <Label htmlFor="shiftReminders" className="text-base font-medium cursor-pointer">
                {notifications.shiftReminders.label}
              </Label>
              <p className="text-sm text-text-secondary">
                {notifications.shiftReminders.description}
              </p>
            </div>
            <Switch
              id="shiftReminders"
              checked={shiftRemindersEnabled}
              onCheckedChange={setShiftRemindersEnabled}
              disabled={isSaving || (isNative && permissionStatus === 'denied')}
            />
          </div>

          {/* Multiple reminder selects - only show when reminders enabled */}
          {shiftRemindersEnabled && (
            <div className="space-y-3">
              <Label className="text-sm font-medium">
                {notifications.shiftReminders.timingLabel}
              </Label>

              {/* Reminder list */}
              <div className="space-y-2">
                {shiftReminderMinutesArray.map((minutes, index) => (
                  <div key={index} className="flex items-center gap-2">
                    <Select
                      value={String(minutes)}
                      onValueChange={(value) => handleChangeReminder(index, Number(value))}
                      disabled={isSaving || (isNative && permissionStatus === 'denied')}
                    >
                      <SelectTrigger className="flex-1">
                        <SelectValue>{getReminderLabel(minutes)}</SelectValue>
                      </SelectTrigger>
                      <SelectContent>
                        {getAvailableOptions(minutes).map((opt) => (
                          <SelectItem key={opt.value} value={String(opt.value)}>
                            {getReminderLabel(opt.value)}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>

                    {/* Remove button - only show if more than 1 reminder */}
                    {shiftReminderMinutesArray.length > 1 && (
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => handleRemoveReminder(index)}
                        disabled={isSaving || (isNative && permissionStatus === 'denied')}
                        className="h-10 w-10 shrink-0 text-text-muted hover:text-text-primary"
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                ))}
              </div>

              {/* Add reminder button - only show if less than max */}
              {shiftReminderMinutesArray.length < MAX_REMINDERS && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleAddReminder}
                  disabled={isSaving || (isNative && permissionStatus === 'denied')}
                  className="w-full"
                >
                  <Plus className="h-4 w-4 mr-2" />
                  {notifications.shiftReminders.addReminder}
                </Button>
              )}

              <p className="text-xs text-text-muted">
                {notifications.shiftReminders.timingHelp}
              </p>
            </div>
          )}

          {/* Divider */}
          <div className="border-t border-border" />

          {/* Summary time setting */}
          <div className="space-y-3">
            <div className="space-y-0.5">
              <Label htmlFor="summaryTime" className="text-base font-medium cursor-pointer">
                {notifications.summaryTime?.label ?? 'Oppsummeringstidspunkt'}
              </Label>
              <p className="text-sm text-text-secondary">
                {notifications.summaryTime?.description ?? 'Når du mottar daglig oppsummering av delte vakter'}
              </p>
            </div>
            <Select
              value={summaryTime}
              onValueChange={setSummaryTime}
              disabled={isSaving || (isNative && permissionStatus === 'denied')}
            >
              <SelectTrigger id="summaryTime" className="w-32">
                <SelectValue>{summaryTime}</SelectValue>
              </SelectTrigger>
              <SelectContent>
                {SUMMARY_TIME_OPTIONS.map((opt) => (
                  <SelectItem key={opt.value} value={opt.value}>
                    {opt.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-text-muted">
              {notifications.summaryTime?.help ?? 'Gjelder kun for kontakter du har satt til daglig oppsummering'}
            </p>
          </div>
        </div>
      </Card>
    </div>
  );
}
