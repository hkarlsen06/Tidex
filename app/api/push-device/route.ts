import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';

/**
 * POST /api/push-device
 *
 * Register or update a push notification device for the authenticated user.
 * Supports both FCM tokens (web/Android) and APNs tokens (iOS native).
 *
 * Body:
 * - apnsToken?: string - APNs device token (iOS native)
 * - fcmToken?: string - FCM token (web/Android/iOS Capacitor)
 * - platform: 'ios' | 'android' | 'web'
 * - deviceId?: string - Device identifier
 * - deviceModel?: string - Device model name
 * - appVersion?: string - App version
 */
export async function POST(request: NextRequest) {
  try {
    // Verify authentication using the user's session
    const supabase = await createSupabaseServerClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = await request.json();
    const { apnsToken, fcmToken, platform, deviceId, deviceModel, appVersion } =
      body;

    // Validate required fields
    if (!platform || !['ios', 'android', 'web'].includes(platform)) {
      return NextResponse.json(
        { error: 'Invalid platform. Must be ios, android, or web' },
        { status: 400 }
      );
    }

    // Must have at least one token
    if (!apnsToken && !fcmToken) {
      return NextResponse.json(
        { error: 'Either apnsToken or fcmToken is required' },
        { status: 400 }
      );
    }

    // Use service client to access internal schema
    const serviceClient = createSupabaseServiceClient();

    // Build the upsert payload
    const payload: Record<string, unknown> = {
      user_id: user.id,
      platform,
      device_id: deviceId ?? null,
      device_model: deviceModel ?? null,
      app_version: appVersion ?? null,
      last_seen_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    // Add tokens if provided
    if (apnsToken) {
      payload.apns_token = apnsToken;
    }
    if (fcmToken) {
      payload.fcm_token = fcmToken;
    }

    // For APNs-only registration, try to update existing record by user_id first
    // This handles the case where FCM token was registered first via Capacitor
    if (apnsToken && !fcmToken) {
      const { data: existingDevice } = await serviceClient
        .schema('internal')
        .from('push_devices')
        .select('id')
        .eq('user_id', user.id)
        .eq('platform', 'ios')
        .maybeSingle();

      if (existingDevice) {
        // Update existing record with APNs token
        const { error: updateError } = await serviceClient
          .schema('internal')
          .from('push_devices')
          .update({
            apns_token: apnsToken,
            device_id: deviceId ?? null,
            device_model: deviceModel ?? null,
            app_version: appVersion ?? null,
            last_seen_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq('id', existingDevice.id);

        if (updateError) {
          console.error('[push-device] Update error:', updateError);
          return NextResponse.json(
            { error: 'Failed to update push device' },
            { status: 500 }
          );
        }

        return NextResponse.json({ success: true, action: 'updated' });
      }

      // No existing record - insert new one
      // Need a placeholder fcm_token since it's required (unique constraint)
      payload.fcm_token = `apns_${apnsToken.substring(0, 32)}`;
    }

    // Upsert with ON CONFLICT on fcm_token
    const { error: upsertError } = await serviceClient
      .schema('internal')
      .from('push_devices')
      .upsert(payload, { onConflict: 'fcm_token' });

    if (upsertError) {
      console.error('[push-device] Upsert error:', upsertError);
      return NextResponse.json(
        { error: 'Failed to register push device' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true, action: 'upserted' });
  } catch (error) {
    console.error('[push-device] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
