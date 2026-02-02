import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import {
  verifyAdminFromRequest,
  isValidUUID,
} from '../../_lib/verify-admin';
import { logAdminAction } from '../../_lib/audit-log';

/**
 * POST /api/admin/users/admin
 *
 * Grant or revoke admin privileges for a user.
 * ONLY the superadmin (SUPERADMIN_USER_ID) can use this endpoint.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 * - Must be the superadmin user
 *
 * Body:
 * - targetUserId: string - The UUID of the user to modify
 * - targetEmail: string - The email of the target user (for logging)
 * - grant: boolean - true to grant admin, false to revoke admin
 *
 * Response:
 * - 200: { success: true, message: string }
 * - 400: { error: string } - Invalid input
 * - 401: { error: string } - Not authenticated
 * - 403: { error: string } - Not superadmin or trying to modify own status
 * - 404: { error: string } - User not found
 * - 500: { error: string } - Server error
 */

interface AdminToggleRequestBody {
  targetUserId: string;
  targetEmail: string;
  grant: boolean;
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

    const { user: admin, isSuperAdmin } = adminResult;
    const adminEmail = admin.email ?? 'unknown';

    // Parse request body
    let body: AdminToggleRequestBody;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { error: 'Invalid JSON body' },
        { status: 400 }
      );
    }

    const { targetUserId, targetEmail, grant } = body;

    // Validate required fields
    if (!targetUserId || typeof targetUserId !== 'string') {
      return NextResponse.json(
        { error: 'Missing or invalid targetUserId' },
        { status: 400 }
      );
    }

    if (typeof grant !== 'boolean') {
      return NextResponse.json(
        { error: 'Missing or invalid grant field (must be boolean)' },
        { status: 400 }
      );
    }

    // GUARDRAIL: Only superadmin can grant/revoke admin privileges
    if (!isSuperAdmin) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: 'Not authorized - only superadmin can manage admin privileges',
          intended_action: grant ? 'grant_admin' : 'revoke_admin',
        },
      });
      return NextResponse.json(
        { error: 'Only superadmin can manage admin privileges' },
        { status: 403 }
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
          intended_action: grant ? 'grant_admin' : 'revoke_admin',
        },
      });
      return NextResponse.json(
        { error: 'Invalid user ID format' },
        { status: 400 }
      );
    }

    // GUARDRAIL: Cannot modify own admin status
    if (targetUserId === admin.id) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: 'Cannot modify own admin status',
          intended_action: grant ? 'grant_admin' : 'revoke_admin',
        },
      });
      return NextResponse.json(
        { error: 'Cannot modify your own admin status' },
        { status: 403 }
      );
    }

    const supabase = createSupabaseServiceClient();

    // Get target user to check current status
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
          intended_action: grant ? 'grant_admin' : 'revoke_admin',
        },
      });
      return NextResponse.json({ error: 'User not found' }, { status: 404 });
    }

    const targetUser = targetUserData.user;
    const currentRole = targetUser.app_metadata?.role as string | undefined;
    const isCurrentlyAdmin = currentRole === 'admin';

    // No change needed
    if (isCurrentlyAdmin === grant) {
      return NextResponse.json({
        success: true,
        message: grant ? 'User is already an admin' : 'User is not an admin',
      });
    }

    // Update the user's app_metadata
    // Note: Supabase merges app_metadata, so we must set role to null to remove it
    const newAppMetadata = { ...targetUser.app_metadata };
    if (grant) {
      newAppMetadata.role = 'admin';
    } else {
      newAppMetadata.role = null;
    }

    const { error: updateError } = await supabase.auth.admin.updateUserById(
      targetUserId,
      {
        app_metadata: newAppMetadata,
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
          intended_action: grant ? 'grant_admin' : 'revoke_admin',
          old_value: { role: currentRole },
        },
      });
      return NextResponse.json(
        {
          error: grant
            ? 'Failed to grant admin privileges'
            : 'Failed to revoke admin privileges',
        },
        { status: 500 }
      );
    }

    // Log successful action
    await logAdminAction({
      adminId: admin.id,
      adminEmail,
      action: grant ? 'grant_admin' : 'revoke_admin',
      targetId: targetUserId,
      targetEmail: targetEmail ?? undefined,
      metadata: {
        old_value: { role: currentRole },
        new_value: { role: grant ? 'admin' : null },
      },
    });

    return NextResponse.json({
      success: true,
      message: grant ? 'Admin privileges granted' : 'Admin privileges revoked',
    });
  } catch (error) {
    console.error('[admin/users/admin] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
