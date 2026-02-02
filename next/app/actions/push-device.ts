'use server';

import { verifySession } from '@/data-access/auth';
import { createSupabaseServiceClient } from '@/lib/supabase/service';

interface RegisterPushDeviceParams {
  fcmToken: string;
  platform: 'ios' | 'android' | 'web';
  deviceId?: string;
  deviceModel?: string;
  appVersion?: string;
}

interface RegisterPushDeviceResult {
  success: boolean;
  error?: string;
}

/**
 * Register or update a push notification device for the current user.
 * Uses service role to access internal.push_devices table.
 */
export async function registerPushDevice(
  params: RegisterPushDeviceParams
): Promise<RegisterPushDeviceResult> {
  try {
    const { user } = await verifySession();
    const supabase = createSupabaseServiceClient();

    // Upsert with ON CONFLICT on fcm_token
    // This handles:
    // 1. New device registration
    // 2. Same device, same user (updates metadata)
    // 3. Same device, different user (updates user_id - account switch)
    const { error } = await supabase
      .schema('internal')
      .from('push_devices')
      .upsert(
        {
          user_id: user.id,
          fcm_token: params.fcmToken,
          platform: params.platform,
          device_id: params.deviceId ?? null,
          device_model: params.deviceModel ?? null,
          app_version: params.appVersion ?? null,
          last_seen_at: new Date().toISOString(),
        },
        {
          onConflict: 'fcm_token',
        }
      );

    if (error) {
      console.error('[registerPushDevice] Error:', error);
      return { success: false, error: error.message };
    }

    return { success: true };
  } catch (e) {
    console.error('[registerPushDevice] Exception:', e);
    return { success: false, error: 'Failed to register push device' };
  }
}

/**
 * Unregister a push notification device by FCM token.
 * Uses service role to access internal.push_devices table.
 *
 * SECURITY: Requires authentication and only allows users to delete their own devices.
 * This prevents attackers from unregistering push tokens they don't own.
 */
export async function unregisterPushDevice(
  fcmToken: string
): Promise<{ success: boolean }> {
  try {
    // Require authentication to prevent unauthorized token deletion
    const { user } = await verifySession();
    const supabase = createSupabaseServiceClient();

    // Only delete if the token belongs to the authenticated user
    const { error } = await supabase
      .schema('internal')
      .from('push_devices')
      .delete()
      .eq('fcm_token', fcmToken)
      .eq('user_id', user.id); // SECURITY: Ensure user owns this token

    if (error) {
      console.error('[unregisterPushDevice] Error:', error);
      return { success: false };
    }

    return { success: true };
  } catch (e) {
    console.error('[unregisterPushDevice] Exception:', e);
    return { success: false };
  }
}

/**
 * Update the last_seen_at timestamp for a push device.
 * Uses service role to access internal.push_devices table.
 *
 * SECURITY: Requires authentication and only allows users to update their own devices.
 */
export async function updatePushDeviceLastSeen(
  fcmToken: string
): Promise<void> {
  try {
    // Require authentication to prevent unauthorized token manipulation
    const { user } = await verifySession();
    const supabase = createSupabaseServiceClient();

    await supabase
      .schema('internal')
      .from('push_devices')
      .update({ last_seen_at: new Date().toISOString() })
      .eq('fcm_token', fcmToken)
      .eq('user_id', user.id); // SECURITY: Ensure user owns this token
  } catch (e) {
    // Non-critical - log but don't throw
    console.error('[updatePushDeviceLastSeen] Exception:', e);
  }
}
