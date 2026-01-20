import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { getSession } from '@/data-access/auth';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { logAdminAction } from '../../_lib/audit-log';

type TargetAudience = 'all' | 'pro' | 'active' | 'specific';

interface SendBroadcastBody {
  title: string;
  body: string;
  deeplink?: string;
  target: TargetAudience;
  specificUserId?: string;
  includeSelf?: boolean;
}

/**
 * Validate deeplink server-side
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
  // Allow query strings: /stats?tab=week
  if (!/^\/[a-zA-Z0-9/_?=&-]*$/.test(deeplink)) {
    return {
      valid: false,
      error:
        'Invalid deeplink format. Must start with / and contain only alphanumeric, /, _, -, ?, =, &',
    };
  }
  // Block path traversal and protocol injection
  if (deeplink.includes('//') || deeplink.includes('..')) {
    return { valid: false, error: 'Invalid deeplink: cannot contain // or ..' };
  }
  return { valid: true, value: deeplink };
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
    let userId: string | null = null;
    let userEmail: string | null = null;
    let userAppMetadata: Record<string, unknown> | null = null;

    // 1. Try Bearer token first (native iOS)
    const authHeader = request.headers.get('Authorization');
    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.substring(7);
      const supabaseWithToken = createClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
        { global: { headers: { Authorization: `Bearer ${token}` } } }
      );
      const { data: { user }, error } = await supabaseWithToken.auth.getUser();
      if (user && !error) {
        userId = user.id;
        userEmail = user.email ?? null;
        userAppMetadata = user.app_metadata ?? {};
      }
    }

    // 2. Fall back to cookie session (web app)
    if (!userId) {
      const session = await getSession();
      if (session) {
        userId = session.user.id;
        userEmail = session.user.email ?? null;
        userAppMetadata = session.user.app_metadata ?? {};
      }
    }

    if (!userId) {
      return NextResponse.json({ error: 'Not authenticated' }, { status: 401 });
    }

    // Verify admin role
    const isAdmin = (userAppMetadata?.role as string) === 'admin';
    if (!isAdmin) {
      return NextResponse.json({ error: 'Access denied' }, { status: 403 });
    }

    // Parse body
    const input: SendBroadcastBody = await request.json();

    // Validate inputs
    if (!input.title || input.title.trim().length === 0) {
      return NextResponse.json(
        { success: false, message: 'Title is required' },
        { status: 400 }
      );
    }
    if (input.title.length > 100) {
      return NextResponse.json(
        { success: false, message: 'Title too long (max 100 chars)' },
        { status: 400 }
      );
    }
    if (!input.body || input.body.trim().length === 0) {
      return NextResponse.json(
        { success: false, message: 'Body is required' },
        { status: 400 }
      );
    }
    if (input.body.length > 500) {
      return NextResponse.json(
        { success: false, message: 'Body too long (max 500 chars)' },
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

    // Validate deeplink
    const deeplinkResult = validateDeeplink(input.deeplink);
    if (!deeplinkResult.valid) {
      return NextResponse.json(
        { success: false, message: deeplinkResult.error },
        { status: 400 }
      );
    }
    const validatedDeeplink = deeplinkResult.value;

    // Service role client for admin operations
    const supabase = createSupabaseServiceClient();

    let targetUserIds: string[] = [];

    if (input.target === 'specific') {
      if (!input.specificUserId) {
        return NextResponse.json(
          { success: false, message: 'User ID required for specific targeting' },
          { status: 400 }
        );
      }
      // Validate UUID format
      if (
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          input.specificUserId
        )
      ) {
        return NextResponse.json(
          { success: false, message: 'Invalid User ID format' },
          { status: 400 }
        );
      }
      targetUserIds = [input.specificUserId];
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

    // Build notification rows for the outbox table
    const allNotifications = targetUserIds.map((targetUserId) => ({
      owner_id: userId,
      recipient_id: targetUserId,
      broadcast_id: broadcastId,
      notification_type: 'admin_broadcast',
      due_at: new Date().toISOString(),
      title: input.title.trim(),
      body: input.body.trim(),
      data_payload: {
        type: 'admin_broadcast',
        deeplink: validatedDeeplink,
        broadcast_id: broadcastId,
      },
      idempotency_key: `broadcast:${broadcastId}:${targetUserId}`,
    }));

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
