import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest, isValidUUID } from '../../_lib/verify-admin';
import { logAdminAction } from '../../_lib/audit-log';

/**
 * POST /api/admin/users/ban
 *
 * Ban or unban a user. Admins cannot ban themselves or other admins.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Body:
 * - targetUserId: string - The UUID of the user to ban/unban
 * - targetEmail: string - The email of the target user (for logging)
 * - ban: boolean - true to ban, false to unban
 *
 * Response:
 * - 200: { success: true, message: string }
 * - 400: { error: string } - Invalid input
 * - 401: { error: string } - Not authenticated
 * - 403: { error: string } - Cannot ban self or other admins
 * - 404: { error: string } - User not found
 * - 500: { error: string } - Server error
 */

// Ban duration: 100 years in hours
const BAN_DURATION_HOURS = '876000h';

interface BanRequestBody {
  targetUserId: string;
  targetEmail: string;
  ban: boolean;
}

export async function POST(request: NextRequest) {
  try {
    // Verify admin authentication
    const adminResult = await verifyAdminFromRequest();

    if (!adminResult) {
      return NextResponse.json(
        { error: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const { user: admin } = adminResult;
    const adminEmail = admin.email ?? 'unknown';

    // Parse request body
    let body: BanRequestBody;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { error: 'Invalid JSON body' },
        { status: 400 }
      );
    }

    const { targetUserId, targetEmail, ban } = body;

    // Validate required fields
    if (!targetUserId || typeof targetUserId !== 'string') {
      return NextResponse.json(
        { error: 'Missing or invalid targetUserId' },
        { status: 400 }
      );
    }

    if (typeof ban !== 'boolean') {
      return NextResponse.json(
        { error: 'Missing or invalid ban field (must be boolean)' },
        { status: 400 }
      );
    }

    // Validate UUID format
    if (!isValidUUID(targetUserId)) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: undefined,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: 'Invalid User ID format',
          intended_action: ban ? 'user_ban' : 'user_unban',
        },
      });
      return NextResponse.json(
        { error: 'Invalid user ID format' },
        { status: 400 }
      );
    }

    // GUARDRAIL: Cannot ban self
    if (targetUserId === admin.id) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: 'Cannot ban self',
          intended_action: 'user_ban',
        },
      });
      return NextResponse.json(
        { error: 'Cannot ban yourself' },
        { status: 403 }
      );
    }

    const supabase = createSupabaseServiceClient();

    // Get target user to check if they're an admin
    const { data: targetUserData, error: getUserError } =
      await supabase.auth.admin.getUserById(targetUserId);

    if (getUserError || !targetUserData?.user) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: getUserError?.message ?? 'User not found',
          intended_action: ban ? 'user_ban' : 'user_unban',
        },
      });
      return NextResponse.json({ error: 'User not found' }, { status: 404 });
    }

    const targetUser = targetUserData.user;
    const isTargetAdmin =
      (targetUser.app_metadata?.role as string | undefined) === 'admin';

    // GUARDRAIL: Cannot ban other admins
    if (ban && isTargetAdmin) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: 'Cannot ban another admin',
          intended_action: 'user_ban',
        },
      });
      return NextResponse.json(
        { error: 'Cannot ban another admin' },
        { status: 403 }
      );
    }

    // Cast to access banned_until which may not be in the type
    const targetUserBannedUntil = (
      targetUser as unknown as { banned_until?: string | null }
    ).banned_until;
    const wasBanned = !!targetUserBannedUntil;

    // No change needed
    if (wasBanned === ban) {
      return NextResponse.json({
        success: true,
        message: ban ? 'User is already banned' : 'User is not banned',
      });
    }

    // Perform the ban/unban
    const { error: updateError } = await supabase.auth.admin.updateUserById(
      targetUserId,
      {
        ban_duration: ban ? BAN_DURATION_HOURS : 'none',
      }
    );

    if (updateError) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: updateError.message,
          intended_action: ban ? 'user_ban' : 'user_unban',
          old_value: { banned: wasBanned },
        },
      });
      return NextResponse.json(
        { error: ban ? 'Failed to ban user' : 'Failed to unban user' },
        { status: 500 }
      );
    }

    // Log successful action
    await logAdminAction({
      adminId: admin.id,
      adminEmail,
      action: ban ? 'user_ban' : 'user_unban',
      targetId: targetUserId,
      targetEmail: targetEmail ?? undefined,
      metadata: {
        old_value: { banned: wasBanned, banned_until: targetUserBannedUntil },
        new_value: { banned: ban },
        ban_duration: ban ? BAN_DURATION_HOURS : null,
      },
    });

    return NextResponse.json({
      success: true,
      message: ban ? 'User banned' : 'User unbanned',
    });
  } catch (error) {
    console.error('[admin/users/ban] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
