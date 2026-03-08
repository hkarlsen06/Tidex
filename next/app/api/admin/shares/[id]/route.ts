import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest, isValidUUID } from '../../_lib/verify-admin';
import { logAdminAction } from '../../_lib/audit-log';

/**
 * PUT /api/admin/shares/[id]
 *
 * Update a shift share's settings.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Body:
 * - showEarnings?: boolean - Whether to show earnings
 * - blocked?: boolean - Whether the share is hidden from the viewer's list
 * - muted?: boolean - Whether notifications are muted
 *
 * Response:
 * - 200: { success: true }
 * - 400: { success: false, message: string } - Validation error or share not found
 * - 401: { success: false, message: string } - Not authenticated or not admin
 * - 500: { success: false, message: string } - Server error
 */
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const adminResult = await verifyAdminFromRequest();

    if (!adminResult) {
      return NextResponse.json(
        { success: false, message: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const { id: shareId } = await params;
    const supabase = createSupabaseServiceClient();
    const adminEmail = adminResult.user.email ?? 'unknown';

    // Validate shareId format
    if (!isValidUUID(shareId)) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Invalid share_id format',
          intended_action: 'shift_share_updated',
          share_id: shareId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Invalid share ID format' },
        { status: 400 }
      );
    }

    let body: {
      showEarnings?: boolean;
      blocked?: boolean;
      muted?: boolean;
    };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { success: false, message: 'Invalid JSON body' },
        { status: 400 }
      );
    }

    const { showEarnings, blocked, muted } = body;

    // Fetch current values for audit diff
    const { data: currentData, error: fetchError } = await supabase
      .from('shift_shares')
      .select('id, owner_id, viewer_id, show_earnings, hidden, muted')
      .eq('id', shareId)
      .single();

    if (fetchError || !currentData) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: fetchError?.message ?? 'Share not found',
          intended_action: 'shift_share_updated',
          share_id: shareId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Share not found' },
        { status: 400 }
      );
    }

    // Get user emails for audit context
    const { data: ownerData } = await supabase.auth.admin.getUserById(
      currentData.owner_id
    );
    const { data: viewerData } = await supabase.auth.admin.getUserById(
      currentData.viewer_id
    );
    const ownerEmail = ownerData?.user?.email ?? null;
    const viewerEmail = viewerData?.user?.email ?? null;

    // Build update object and track changes
    const updates: Record<string, unknown> = {};
    const changes: Record<string, { before: unknown; after: unknown }> = {};

    if (
      showEarnings !== undefined &&
      showEarnings !== currentData.show_earnings
    ) {
      updates.show_earnings = showEarnings;
      changes.show_earnings = {
        before: currentData.show_earnings,
        after: showEarnings,
      };
    }

    if (blocked !== undefined && blocked !== currentData.hidden) {
      updates.hidden = blocked;
      changes.blocked = {
        before: currentData.hidden,
        after: blocked,
      };
    }

    if (muted !== undefined && muted !== currentData.muted) {
      updates.muted = muted;
      changes.muted = {
        before: currentData.muted,
        after: muted,
      };
    }

    // No changes to make
    if (Object.keys(updates).length === 0) {
      return NextResponse.json({ success: true });
    }

    // Perform the update
    const { error: updateError } = await supabase
      .from('shift_shares')
      .update(updates)
      .eq('id', shareId);

    if (updateError) {
      console.error('[admin/shares] Update error:', updateError);
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: shareId,
        metadata: {
          error: updateError.message,
          intended_action: 'shift_share_updated',
          share_id: shareId,
          owner_id: currentData.owner_id,
          viewer_id: currentData.viewer_id,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Failed to update share' },
        { status: 500 }
      );
    }

    // Log successful action with before/after diff
    await logAdminAction({
      adminId: adminResult.user.id,
      adminEmail,
      action: 'shift_share_updated',
      targetId: shareId,
      metadata: {
        share_id: shareId,
        owner_id: currentData.owner_id,
        owner_email: ownerEmail,
        viewer_id: currentData.viewer_id,
        viewer_email: viewerEmail,
        changes,
      },
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('[admin/shares] PUT exception:', error);
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * DELETE /api/admin/shares/[id]
 *
 * Delete a shift share.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Response:
 * - 200: { success: true }
 * - 400: { success: false, message: string } - Validation error or share not found
 * - 401: { success: false, message: string } - Not authenticated or not admin
 * - 500: { success: false, message: string } - Server error
 */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const adminResult = await verifyAdminFromRequest();

    if (!adminResult) {
      return NextResponse.json(
        { success: false, message: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const { id: shareId } = await params;
    const supabase = createSupabaseServiceClient();
    const adminEmail = adminResult.user.email ?? 'unknown';

    // Validate shareId format
    if (!isValidUUID(shareId)) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Invalid share_id format',
          intended_action: 'shift_share_deleted',
          share_id: shareId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Invalid share ID format' },
        { status: 400 }
      );
    }

    // Fetch share details before delete for audit
    const { data: shareData, error: fetchError } = await supabase
      .from('shift_shares')
      .select(
        'id, owner_id, viewer_id, show_earnings, hidden, muted, created_at'
      )
      .eq('id', shareId)
      .single();

    if (fetchError || !shareData) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: fetchError?.message ?? 'Share not found',
          intended_action: 'shift_share_deleted',
          share_id: shareId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Share not found' },
        { status: 400 }
      );
    }

    // Get user emails for audit context
    const { data: ownerData } = await supabase.auth.admin.getUserById(
      shareData.owner_id
    );
    const { data: viewerData } = await supabase.auth.admin.getUserById(
      shareData.viewer_id
    );
    const ownerEmail = ownerData?.user?.email ?? null;
    const viewerEmail = viewerData?.user?.email ?? null;

    // Delete the share
    const { error: deleteError } = await supabase
      .from('shift_shares')
      .delete()
      .eq('id', shareId);

    if (deleteError) {
      console.error('[admin/shares] Delete error:', deleteError);
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: shareId,
        metadata: {
          error: deleteError.message,
          intended_action: 'shift_share_deleted',
          share_id: shareId,
          owner_id: shareData.owner_id,
          viewer_id: shareData.viewer_id,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Failed to delete share' },
        { status: 500 }
      );
    }

    // Log successful action with full context
    await logAdminAction({
      adminId: adminResult.user.id,
      adminEmail,
      action: 'shift_share_deleted',
      targetId: shareId,
      metadata: {
        share_id: shareId,
        owner_id: shareData.owner_id,
        owner_email: ownerEmail,
        viewer_id: shareData.viewer_id,
        viewer_email: viewerEmail,
        deleted_data: {
          show_earnings: shareData.show_earnings,
          blocked: shareData.hidden,
          muted: shareData.muted,
          created_at: shareData.created_at,
        },
      },
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('[admin/shares] DELETE exception:', error);
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}
