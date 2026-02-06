import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/data-access/auth';
import { createSupabaseServiceClient } from '@/lib/supabase/service';

/**
 * POST /api/push-device
 *
 * Register or update a push notification device for the authenticated user.
 * Supports both FCM tokens (web/Android) and APNs tokens (iOS native).
 *
 * Authentication:
 * - Cookie-based session (web app) - handled by getSession
 * - Bearer token in Authorization header (native iOS app) - handled by getSession
 *
 * Body:
 * - apnsToken?: string - APNs device token (iOS native)
 * - fcmToken?: string - FCM token (web/Android/iOS app)
 * - platform: 'ios' | 'android' | 'web'
 * - deviceId?: string - Device identifier
 * - deviceModel?: string - Device model name
 * - appVersion?: string - App version
 */
export async function POST(request: NextRequest) {
  try {
    // getSession now handles both Bearer tokens (iOS) and cookies (web)
    const session = await getSession();
    if (!session) {
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
    const now = new Date().toISOString();

    // Build the payload
    const payload: Record<string, unknown> = {
      user_id: session.user.id,
      platform,
      device_id: deviceId ?? null,
      device_model: deviceModel ?? null,
      app_version: appVersion ?? null,
      last_seen_at: now,
      updated_at: now,
    };

    // Add tokens if provided
    if (apnsToken) {
      payload.apns_token = apnsToken;
    }
    if (fcmToken) {
      payload.fcm_token = fcmToken;
    }

    // DEDUPLICATION: Find existing device by device_id first (most reliable)
    // This prevents duplicate entries when tokens change
    let existingDeviceId: string | null = null;

    if (deviceId) {
      const { data: deviceMatch } = await serviceClient
        .schema('internal')
        .from('push_devices')
        .select('id')
        .eq('user_id', session.user.id)
        .eq('device_id', deviceId)
        .maybeSingle();

      existingDeviceId = deviceMatch?.id ?? null;
    }

    // Fall back to matching by fcm_token if no device_id match
    if (!existingDeviceId && fcmToken) {
      const { data: tokenMatch } = await serviceClient
        .schema('internal')
        .from('push_devices')
        .select('id')
        .eq('fcm_token', fcmToken)
        .maybeSingle();

      existingDeviceId = tokenMatch?.id ?? null;
    }

    // Fall back to user_id + platform for APNs-only registrations
    if (!existingDeviceId && apnsToken && !fcmToken) {
      const { data: platformMatch } = await serviceClient
        .schema('internal')
        .from('push_devices')
        .select('id')
        .eq('user_id', session.user.id)
        .eq('platform', platform)
        .order('updated_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      existingDeviceId = platformMatch?.id ?? null;
    }

    // CROSS-USER DEDUP: Clear any existing rows with the same APNs token
    // belonging to a DIFFERENT user. This prevents stale tokens from
    // impersonation sessions or account switches delivering notifications
    // to the wrong device.
    if (apnsToken) {
      await serviceClient
        .schema('internal')
        .from('push_devices')
        .delete()
        .eq('apns_token', apnsToken)
        .neq('user_id', session.user.id);
    }

    if (existingDeviceId) {
      // Update existing record
      const updatePayload: Record<string, unknown> = {
        device_id: deviceId ?? null,
        device_model: deviceModel ?? null,
        app_version: appVersion ?? null,
        last_seen_at: now,
        updated_at: now,
      };

      // Update tokens if provided
      if (apnsToken) {
        updatePayload.apns_token = apnsToken;
      }
      if (fcmToken) {
        updatePayload.fcm_token = fcmToken;
      }

      const { error: updateError } = await serviceClient
        .schema('internal')
        .from('push_devices')
        .update(updatePayload)
        .eq('id', existingDeviceId);

      if (updateError) {
        console.error('[push-device] Update error:', updateError);
        return NextResponse.json(
          { error: 'Failed to update push device' },
          { status: 500 }
        );
      }

      // Clean up any other duplicate entries for this device_id
      if (deviceId) {
        await serviceClient
          .schema('internal')
          .from('push_devices')
          .delete()
          .eq('user_id', session.user.id)
          .eq('device_id', deviceId)
          .neq('id', existingDeviceId);
      }

      return NextResponse.json({ success: true, action: 'updated' });
    }

    // No existing record - insert new one
    // For APNs-only, generate a placeholder fcm_token (unique constraint)
    if (apnsToken && !fcmToken) {
      payload.fcm_token = `apns_${apnsToken.substring(0, 32)}`;
    }

    const { error: insertError } = await serviceClient
      .schema('internal')
      .from('push_devices')
      .insert(payload);

    if (insertError) {
      // Handle unique constraint violation (race condition - another request already inserted)
      // PostgreSQL error code 23505 = unique_violation
      if (insertError.code === '23505') {
        console.log(
          '[push-device] Device already registered (race condition), treating as success'
        );
        return NextResponse.json({ success: true, action: 'already_registered' });
      }

      console.error('[push-device] Insert error:', insertError);
      return NextResponse.json(
        { error: 'Failed to register push device' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true, action: 'inserted' });
  } catch (error) {
    console.error('[push-device] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
