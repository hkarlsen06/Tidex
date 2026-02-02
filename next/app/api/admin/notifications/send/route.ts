import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/data-access/auth';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { logAdminAction } from '../../_lib/audit-log';

type TargetAudience = 'all' | 'pro' | 'active' | 'specific';

interface SendBroadcastBody {
  title: string;       // English
  titleNo: string;     // Norwegian
  body: string;        // English
  bodyNo: string;      // Norwegian
  deeplink?: string;   // English
  deeplinkNo?: string; // Norwegian (optional, falls back to English)
  target: TargetAudience;
  specificUserId?: string; // Legacy single user support
  specificUserIds?: string[]; // Multiple users support
  includeSelf?: boolean;
}

/**
 * Validate deeplink server-side - allows any URL format
 * Returns error message or null if valid
 */
function validateDeeplink(
  deeplink: string | undefined
): { valid: true; value: string | null } | { valid: false; error: string } {
  if (!deeplink || deeplink.trim() === '') {
    return { valid: true, value: null };
  }
  // Max length check
  if (deeplink.length > 200) {
    return { valid: false, error: 'Deeplink too long (max 200 chars)' };
  }
  // Block path traversal
  if (deeplink.includes('..')) {
    return { valid: false, error: 'Invalid deeplink: cannot contain ..' };
  }
  return { valid: true, value: deeplink.trim() };
}

const BATCH_SIZE = 500; // Supabase insert limit safety

/**
 * POST /api/admin/notifications/send
 *
 * Sends a broadcast notification to targeted users.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 *
 * Authorization:
 * - User must have admin role in app_metadata
 *
 * Body:
 * - title: string - Notification title (max 100 chars)
 * - body: string - Notification body (max 500 chars)
 * - deeplink?: string - Optional deeplink path (max 200 chars)
 * - target: 'all' | 'pro' | 'active' | 'specific' - Target audience
 * - specificUserId?: string - Required if target is 'specific'
 * - includeSelf?: boolean - Include sending admin in broadcast
 *
 * Response:
 * - 200: { success: true, message: string }
 * - 400: { success: false, message: string } - Validation error
 * - 401: { error: string } - Not authenticated
 * - 403: { error: string } - Not authorized (not admin)
 * - 500: { error: string } - Server error
 */
export async function POST(request: NextRequest) {
  try {
    // getSession handles both Bearer tokens (iOS) and cookies (web)
    const session = await getSession();
    if (!session) {
      return NextResponse.json({ error: 'Not authenticated' }, { status: 401 });
    }

    const userId = session.user.id;
    const userEmail = session.user.email ?? null;

    // Verify admin role
    const isAdmin = (session.user.app_metadata?.role as string) === 'admin';
    if (!isAdmin) {
      return NextResponse.json({ error: 'Access denied' }, { status: 403 });
    }

    // Parse body
    const input: SendBroadcastBody = await request.json();

    // Validate English inputs
    if (!input.title || input.title.trim().length === 0) {
      return NextResponse.json(
        { success: false, message: 'English title is required' },
        { status: 400 }
      );
    }
    if (input.title.length > 100) {
      return NextResponse.json(
        { success: false, message: 'English title too long (max 100 chars)' },
        { status: 400 }
      );
    }
    if (!input.body || input.body.trim().length === 0) {
      return NextResponse.json(
        { success: false, message: 'English body is required' },
        { status: 400 }
      );
    }
    if (input.body.length > 500) {
      return NextResponse.json(
        { success: false, message: 'English body too long (max 500 chars)' },
        { status: 400 }
      );
    }

    // Validate Norwegian inputs
    if (!input.titleNo || input.titleNo.trim().length === 0) {
      return NextResponse.json(
        { success: false, message: 'Norwegian title is required' },
        { status: 400 }
      );
    }
    if (input.titleNo.length > 100) {
      return NextResponse.json(
        { success: false, message: 'Norwegian title too long (max 100 chars)' },
        { status: 400 }
      );
    }
    if (!input.bodyNo || input.bodyNo.trim().length === 0) {
      return NextResponse.json(
        { success: false, message: 'Norwegian body is required' },
        { status: 400 }
      );
    }
    if (input.bodyNo.length > 500) {
      return NextResponse.json(
        { success: false, message: 'Norwegian body too long (max 500 chars)' },
        { status: 400 }
      );
    }

    // Validate target
    if (!['all', 'pro', 'active', 'specific'].includes(input.target)) {
      return NextResponse.json(
        { success: false, message: 'Invalid target. Must be all, pro, active, or specific' },
        { status: 400 }
      );
    }

    // Validate deeplinks
    const deeplinkResult = validateDeeplink(input.deeplink);
    if (!deeplinkResult.valid) {
      return NextResponse.json(
        { success: false, message: `English deeplink: ${deeplinkResult.error}` },
        { status: 400 }
      );
    }
    const validatedDeeplink = deeplinkResult.value;

    const deeplinkNoResult = validateDeeplink(input.deeplinkNo);
    if (!deeplinkNoResult.valid) {
      return NextResponse.json(
        { success: false, message: `Norwegian deeplink: ${deeplinkNoResult.error}` },
        { status: 400 }
      );
    }
    const validatedDeeplinkNo = deeplinkNoResult.value;

    // Service role client for admin operations
    const supabase = createSupabaseServiceClient();

    let targetUserIds: string[] = [];

    if (input.target === 'specific') {
      // Support both single user (legacy) and multiple users
      const userIds = input.specificUserIds ?? (input.specificUserId ? [input.specificUserId] : []);

      if (userIds.length === 0) {
        return NextResponse.json(
          { success: false, message: 'At least one user ID required for specific targeting' },
          { status: 400 }
        );
      }

      if (userIds.length > 100) {
        return NextResponse.json(
          { success: false, message: 'Maximum 100 users per broadcast' },
          { status: 400 }
        );
      }

      // Validate all UUID formats
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      for (const id of userIds) {
        if (!uuidRegex.test(id)) {
          return NextResponse.json(
            { success: false, message: `Invalid User ID format: ${id}` },
            { status: 400 }
          );
        }
      }

      targetUserIds = userIds;
    } else {
      // Use hardened admin RPC functions (service_role only)
      const excludeUserId = input.includeSelf ? null : userId;

      let rpcName: string;
      let rpcParams: Record<string, unknown> = {};

      switch (input.target) {
        case 'pro':
          rpcName = 'admin_get_target_users_pro';
          break;
        case 'active':
          rpcName = 'admin_get_target_users_active';
          break;
        default: // 'all'
          rpcName = 'admin_get_target_users_all';
          rpcParams = { exclude_user_id: excludeUserId };
      }

      const { data, error } = await supabase.rpc(rpcName, rpcParams);
      if (error) {
        return NextResponse.json(
          { success: false, message: `Targeting failed: ${error.message}` },
          { status: 500 }
        );
      }
      targetUserIds = (data || []).map((r: { user_id: string }) => r.user_id);
    }

    if (targetUserIds.length === 0) {
      return NextResponse.json(
        { success: false, message: 'No users match target criteria' },
        { status: 400 }
      );
    }

    // Create broadcast record
    const { data: broadcast, error: broadcastError } = await supabase
      .schema('internal')
      .from('admin_broadcasts')
      .insert({
        admin_id: userId,
        title: input.title.trim(),
        body: input.body.trim(),
        deeplink: validatedDeeplink,
        target: input.target,
        target_count: targetUserIds.length,
      })
      .select('id')
      .single();

    if (broadcastError || !broadcast) {
      return NextResponse.json(
        { success: false, message: `Failed to create broadcast: ${broadcastError?.message}` },
        { status: 500 }
      );
    }

    const broadcastId = broadcast.id;

    // Fetch user locales for all target users via RPC
    const { data: userLocales } = await supabase.rpc('admin_get_user_locales', {
      user_ids: targetUserIds,
    });

    // Build a map of user ID to locale
    const localeMap = new Map<string, string>();
    if (userLocales) {
      for (const u of userLocales as { user_id: string; locale: string | null }[]) {
        localeMap.set(u.user_id, u.locale ?? 'en');
      }
    }

    // Helper to determine if a locale is Norwegian
    const isNorwegian = (locale: string | undefined) => {
      if (!locale) return false;
      const l = locale.toLowerCase();
      return l === 'no' || l === 'nb' || l === 'nn' || l.startsWith('no-') || l.startsWith('nb-') || l.startsWith('nn-');
    };

    // Build notification rows for the outbox table with localized content
    const allNotifications = targetUserIds.map((targetUserId) => {
      const userLocale = localeMap.get(targetUserId);
      const useNorwegian = isNorwegian(userLocale);

      const localizedTitle = useNorwegian ? input.titleNo.trim() : input.title.trim();
      const localizedBody = useNorwegian ? input.bodyNo.trim() : input.body.trim();
      // Norwegian deeplink falls back to English if not provided
      const localizedDeeplink = useNorwegian && validatedDeeplinkNo
        ? validatedDeeplinkNo
        : validatedDeeplink;

      return {
        owner_id: userId,
        recipient_id: targetUserId,
        broadcast_id: broadcastId,
        notification_type: 'admin_broadcast',
        due_at: new Date().toISOString(),
        title: localizedTitle,
        body: localizedBody,
        data_payload: {
          type: 'admin_broadcast',
          deeplink: localizedDeeplink,
          broadcast_id: broadcastId,
        },
        idempotency_key: `broadcast:${broadcastId}:${targetUserId}`,
      };
    });

    // Batch insert to avoid payload size limits
    let insertedCount = 0;
    for (let i = 0; i < allNotifications.length; i += BATCH_SIZE) {
      const batch = allNotifications.slice(i, i + BATCH_SIZE);
      const { error: insertError } = await supabase
        .schema('internal')
        .from('notifications_outbox')
        .insert(batch);

      if (insertError) {
        // Partial failure - update broadcast status
        await supabase
          .schema('internal')
          .from('admin_broadcasts')
          .update({ status: 'partial_failure' })
          .eq('id', broadcastId);

        return NextResponse.json(
          {
            success: false,
            message: `Queue failed at batch ${Math.floor(i / BATCH_SIZE) + 1}: ${insertError.message}. ${insertedCount} notifications queued before failure.`,
          },
          { status: 500 }
        );
      }
      insertedCount += batch.length;
    }

    // All batches inserted - update status to 'queued'
    await supabase
      .schema('internal')
      .from('admin_broadcasts')
      .update({ status: 'queued' })
      .eq('id', broadcastId);

    // Trigger edge function
    try {
      await supabase.functions.invoke('send-push-notifications');
    } catch (e) {
      console.error(
        '[admin/notifications/send] Failed to trigger push function (notifications still queued):',
        e
      );
    }

    // Log successful broadcast action
    await logAdminAction({
      adminId: userId,
      adminEmail: userEmail ?? 'unknown',
      action: 'broadcast_sent',
      metadata: {
        broadcast_id: broadcastId,
        title: input.title.trim(),
        target: input.target,
        target_count: targetUserIds.length,
        deeplink: validatedDeeplink,
      },
    });

    return NextResponse.json({
      success: true,
      message: `Notification queued for ${targetUserIds.length} user${targetUserIds.length === 1 ? '' : 's'}`,
    });
  } catch (error) {
    console.error('[admin/notifications/send] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
