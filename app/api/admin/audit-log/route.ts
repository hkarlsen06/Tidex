import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest, isValidUUID, isNextInternalError } from '../_lib/verify-admin';
import type { AdminAction } from '@/lib/admin/action-labels';

/**
 * GET /api/admin/audit-log
 *
 * Retrieves the admin audit log with optional filtering.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Query Parameters:
 * - limit: number - Maximum entries to return (default: 50)
 * - actionFilter: string - Filter by action type (e.g., "user_ban", "grant_admin")
 * - targetFilter: string - Filter by target user ID (UUID)
 *
 * Response:
 * - 200: { success: true, entries: AuditLogEntry[] }
 * - 400: { success: false, message: string } - Invalid parameters
 * - 401: { success: false, message: string } - Not authenticated
 * - 403: { success: false, message: string } - Not an admin
 * - 500: { success: false, message: string } - Server error
 */

interface AuditLogEntry {
  id: string;
  adminId: string | null;
  adminEmail: string | null;
  action: AdminAction;
  targetUserId: string | null;
  targetEmail: string | null;
  metadata: Record<string, unknown>;
  createdAt: string;
}

interface AuditLogRow {
  id: string;
  admin_id: string | null;
  admin_email: string | null;
  action: AdminAction;
  target_user_id: string | null;
  target_email: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
}

export async function GET(request: NextRequest) {
  try {
    // Verify admin authentication
    const adminResult = await verifyAdminFromRequest(request);

    if (!adminResult) {
      return NextResponse.json(
        { success: false, message: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    // Parse query parameters
    const searchParams = request.nextUrl.searchParams;
    const limitParam = searchParams.get('limit');
    const actionFilter = searchParams.get('actionFilter');
    const targetFilter = searchParams.get('targetFilter');

    // Validate limit
    const limit = limitParam ? parseInt(limitParam, 10) : 50;
    if (isNaN(limit) || limit < 1 || limit > 1000) {
      return NextResponse.json(
        { success: false, message: 'Invalid limit parameter (must be 1-1000)' },
        { status: 400 }
      );
    }

    // Validate target filter UUID if provided
    if (targetFilter && !isValidUUID(targetFilter)) {
      return NextResponse.json(
        { success: false, message: 'Invalid target user ID format' },
        { status: 400 }
      );
    }

    const supabase = createSupabaseServiceClient();

    const { data, error } = await supabase.rpc('admin_get_audit_log', {
      p_limit: limit,
      p_action_filter: actionFilter ?? null,
      p_target_filter: targetFilter ?? null,
    });

    if (error) {
      console.error('[admin/audit-log] RPC error:', error);
      return NextResponse.json(
        { success: false, message: 'Failed to fetch audit log' },
        { status: 500 }
      );
    }

    // Transform snake_case to camelCase for Swift Codable compatibility
    const entries: AuditLogEntry[] = ((data as AuditLogRow[]) ?? []).map(
      (row) => ({
        id: row.id,
        adminId: row.admin_id,
        adminEmail: row.admin_email,
        action: row.action,
        targetUserId: row.target_user_id,
        targetEmail: row.target_email,
        metadata: row.metadata ?? {},
        createdAt: row.created_at,
      })
    );

    return NextResponse.json(
      { success: true, entries },
      {
        headers: {
          'Cache-Control': 'private, max-age=30, stale-while-revalidate=10',
        },
      }
    );
  } catch (error) {
    // Re-throw Next.js internal errors (prerender bailout, etc.)
    if (isNextInternalError(error)) throw error;
    console.error('[admin/audit-log] Exception:', error);
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}
