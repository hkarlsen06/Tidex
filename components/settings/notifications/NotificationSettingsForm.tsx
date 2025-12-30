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
} from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { pushNotificationService } from '@/lib/notifications/push-service';
import { isNativePlatform } from '@/lib/capacitor/platform';
import { useRouter } from 'next/navigation';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

type PermissionStatus = 'granted' | 'denied' | 'prompt' | 'unknown';

interface NotificationSettingsFormProps {
  initialData: {
    sharedShiftsEnabled: boolean;
    shiftRemindersEnabled: boolean;
    shiftReminderMinutes: number;
  };
  t: Dictionary;
}

export function NotificationSettingsForm({ initialData, t }: NotificationSettingsFormProps) {
  const router = useRouter();
  const isInitialMount = useRef(true);
  const isReminderInitialMount = useRef(true);
  const [sharedShiftsEnabled, setSharedShiftsEnabled] = useState(initialData.sharedShiftsEnabled);
  const [shiftRemindersEnabled, setShiftRemindersEnabled] = useState(initialData.shiftRemindersEnabled);
  const [shiftReminderMinutes, setShiftReminderMinutes] = useState(initialData.shiftReminderMinutes);
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
          shift_reminder_minutes: shiftReminderMinutes,
        });
        router.refresh();
      } catch (error) {
        console.error('Failed to save shift reminder settings:', error);
      } finally {
        setIsSaving(false);
      }
    };

    saveReminderPreferences();
  }, [shiftRemindersEnabled, shiftReminderMinutes, router]);

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

          {/* Reminder timing select - only show when reminders enabled */}
          {shiftRemindersEnabled && (
            <div className="ml-0 space-y-2">
              <Label htmlFor="reminderTiming" className="text-sm font-medium">
                {notifications.shiftReminders.timingLabel}
              </Label>
              <Select
                value={String(shiftReminderMinutes)}
                onValueChange={(value) => setShiftReminderMinutes(Number(value))}
                disabled={isSaving || (isNative && permissionStatus === 'denied')}
              >
                <SelectTrigger id="reminderTiming" className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="60">{notifications.shiftReminders.options.hour1}</SelectItem>
                  <SelectItem value="120">{notifications.shiftReminders.options.hour2}</SelectItem>
                  <SelectItem value="300">{notifications.shiftReminders.options.hour5}</SelectItem>
                  <SelectItem value="1440">{notifications.shiftReminders.options.hour24}</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-text-muted">
                {notifications.shiftReminders.timingHelp}
              </p>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
}
