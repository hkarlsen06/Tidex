import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest, isValidUUID } from '../../_lib/verify-admin';
import { logAdminAction } from '../../_lib/audit-log';

/**
 * POST /api/admin/users/grandfathered
 *
 * Grant or revoke grandfathered (lifetime access) status for a user.
 * Any admin can use this endpoint.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Body:
 * - targetUserId: string - The UUID of the user to modify
 * - targetEmail: string - The email of the target user (for logging)
 * - grant: boolean - true to grant grandfathered status, false to revoke
 *
 * Response:
 * - 200: { success: true, message: string }
 * - 400: { error: string } - Invalid input
 * - 401: { error: string } - Not authenticated
 * - 404: { error: string } - User not found
 * - 500: { error: string } - Server error
 */

interface GrandfatheredToggleRequestBody {
  targetUserId: string;
  targetEmail: string;
  grant: boolean;
}

export async function POST(request: NextRequest) {
  try {
    // Verify admin authentication
    const adminResult = await verifyAdminFromRequest(request);

    if (!adminResult) {
      return NextResponse.json(
        { error: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const { user: admin } = adminResult;
    const adminEmail = admin.email ?? 'unknown';

    // Parse request body
    let body: GrandfatheredToggleRequestBody;
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
          intended_action: grant ? 'grant_grandfathered' : 'revoke_grandfathered',
        },
      });
      return NextResponse.json(
        { error: 'Invalid user ID format' },
        { status: 400 }
      );
    }

    const supabase = createSupabaseServiceClient();

    // Get current state
    const { data: profile, error: fetchError } = await supabase
      .from('profiles')
      .select('before_paywall')
      .eq('id', targetUserId)
      .single();

    if (fetchError || !profile) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: fetchError?.message ?? 'Profile not found',
          intended_action: grant ? 'grant_grandfathered' : 'revoke_grandfathered',
        },
      });
      return NextResponse.json({ error: 'User not found' }, { status: 404 });
    }

    const oldValue = profile.before_paywall;
    const newValue = grant;

    // No change needed
    if (oldValue === newValue) {
      return NextResponse.json({
        success: true,
        message: grant
          ? 'User already has lifetime access'
          : 'User does not have lifetime access',
      });
    }

    // Update the profile
    const { error: updateError } = await supabase
      .from('profiles')
      .update({
        before_paywall: newValue,
        updated_at: new Date().toISOString(),
      })
      .eq('id', targetUserId);

    if (updateError) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail: targetEmail ?? undefined,
        metadata: {
          error: updateError.message,
          intended_action: grant ? 'grant_grandfathered' : 'revoke_grandfathered',
          old_value: oldValue,
        },
      });
      return NextResponse.json(
        { error: 'Failed to update user' },
        { status: 500 }
      );
    }

    // Log successful action
    await logAdminAction({
      adminId: admin.id,
      adminEmail,
      action: grant ? 'grant_grandfathered' : 'revoke_grandfathered',
      targetId: targetUserId,
      targetEmail: targetEmail ?? undefined,
      metadata: {
        old_value: oldValue,
        new_value: newValue,
      },
    });

    return NextResponse.json({
      success: true,
      message: grant ? 'Lifetime access granted' : 'Lifetime access revoked',
    });
  } catch (error) {
    console.error('[admin/users/grandfathered] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
