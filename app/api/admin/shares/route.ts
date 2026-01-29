import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest, isValidUUID } from '../_lib/verify-admin';
import { logAdminAction } from '../_lib/audit-log';

/**
 * Shift share item returned to clients
 */
interface ShiftShareItem {
  id: string;
  ownerId: string;
  ownerEmail: string | null;
  ownerName: string | null;
  ownerPhone: string | null;
  viewerId: string;
  viewerEmail: string | null;
  viewerName: string | null;
  viewerPhone: string | null;
  createdAt: string;
  showEarnings: boolean;
  blocked: boolean;
  muted: boolean;
}

/**
 * Raw row from admin_execute_sql query
 */
interface ShiftShareRow {
  id: string;
  owner_id: string;
  owner_email: string | null;
  owner_name: string | null;
  owner_phone: string | null;
  viewer_id: string;
  viewer_email: string | null;
  viewer_name: string | null;
  viewer_phone: string | null;
  created_at: string;
  show_earnings: boolean;
  blocked: boolean;
  muted: boolean;
}

/**
 * GET /api/admin/shares
 *
 * List all shift shares with pagination and search.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Query Parameters:
 * - search: string - Search term for owner/viewer email, name, phone, or ID
 * - page: number - Page number (1-indexed, default: 1)
 * - pageSize: number - Items per page (default: 20)
 * - sortBy: "created_at" | "owner_name" | "viewer_name" - Sort field (default: "created_at")
 * - sortOrder: "asc" | "desc" - Sort direction (default: "desc")
 *
 * Response:
 * - 200: { success: true, shares: ShiftShareItem[], totalCount: number, page: number, pageSize: number }
 * - 401: { success: false, message: string } - Not authenticated or not admin
 * - 500: { success: false, message: string } - Server error
 */
export async function GET(request: NextRequest) {
  try {
    const adminResult = await verifyAdminFromRequest();

    if (!adminResult) {
      return NextResponse.json(
        { success: false, message: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const supabase = createSupabaseServiceClient();

    // Parse query parameters
    const searchParams = request.nextUrl.searchParams;
    const page = Math.max(1, parseInt(searchParams.get('page') ?? '1', 10));
    const pageSize = Math.max(
      1,
      Math.min(100, parseInt(searchParams.get('pageSize') ?? '20', 10))
    );
    const sortBy = searchParams.get('sortBy') ?? 'created_at';
    const sortOrder = searchParams.get('sortOrder') ?? 'desc';
    const search = searchParams.get('search')?.trim().toLowerCase() ?? '';

    // Validate sortBy
    const validSortBy = ['created_at', 'owner_name', 'viewer_name'];
    if (!validSortBy.includes(sortBy)) {
      return NextResponse.json(
        {
          success: false,
          message: `Invalid sortBy. Must be one of: ${validSortBy.join(', ')}`,
        },
        { status: 400 }
      );
    }

    // Validate sortOrder
    if (sortOrder !== 'asc' && sortOrder !== 'desc') {
      return NextResponse.json(
        { success: false, message: 'Invalid sortOrder. Must be asc or desc' },
        { status: 400 }
      );
    }

    // Build the SQL order clause
    let orderClause: string;
    switch (sortBy) {
      case 'owner_name':
        orderClause = `COALESCE(o.raw_user_meta_data->>'full_name', o.email, o.phone, ss.owner_id::text) ${sortOrder}`;
        break;
      case 'viewer_name':
        orderClause = `COALESCE(v.raw_user_meta_data->>'full_name', v.email, v.phone, ss.viewer_id::text) ${sortOrder}`;
        break;
      default:
        orderClause = `ss.created_at ${sortOrder}`;
    }

    // Build search filter
    let searchFilter = '';
    if (search) {
      // Escape single quotes for SQL safety
      const escapedSearch = search.replace(/'/g, "''");
      searchFilter = `
        AND (
          LOWER(o.email) LIKE '%${escapedSearch}%'
          OR LOWER(o.phone) LIKE '%${escapedSearch}%'
          OR LOWER(o.raw_user_meta_data->>'full_name') LIKE '%${escapedSearch}%'
          OR LOWER(ss.owner_id::text) LIKE '%${escapedSearch}%'
          OR LOWER(v.email) LIKE '%${escapedSearch}%'
          OR LOWER(v.phone) LIKE '%${escapedSearch}%'
          OR LOWER(v.raw_user_meta_data->>'full_name') LIKE '%${escapedSearch}%'
          OR LOWER(ss.viewer_id::text) LIKE '%${escapedSearch}%'
        )
      `;
    }

    // Get total count
    const countQuery = `
      SELECT COUNT(*) as count
      FROM shift_shares ss
      LEFT JOIN auth.users o ON ss.owner_id = o.id
      LEFT JOIN auth.users v ON ss.viewer_id = v.id
      WHERE 1=1 ${searchFilter}
    `;

    const { data: countData, error: countError } = await supabase.rpc(
      'admin_execute_sql',
      { sql_query: countQuery }
    );

    if (countError) {
      console.error('[admin/shares] Count error:', countError);
      return NextResponse.json(
        { success: false, message: 'Failed to count shares' },
        { status: 500 }
      );
    }

    const totalCount = countData?.[0]?.count ?? 0;

    // Get paginated results
    const offset = (page - 1) * pageSize;
    const dataQuery = `
      SELECT
        ss.id,
        ss.owner_id,
        o.email as owner_email,
        o.raw_user_meta_data->>'full_name' as owner_name,
        o.phone as owner_phone,
        ss.viewer_id,
        v.email as viewer_email,
        v.raw_user_meta_data->>'full_name' as viewer_name,
        v.phone as viewer_phone,
        ss.created_at,
        ss.show_earnings,
        ss.blocked,
        ss.muted
      FROM shift_shares ss
      LEFT JOIN auth.users o ON ss.owner_id = o.id
      LEFT JOIN auth.users v ON ss.viewer_id = v.id
      WHERE 1=1 ${searchFilter}
      ORDER BY ${orderClause}
      LIMIT ${pageSize}
      OFFSET ${offset}
    `;

    const { data, error } = await supabase.rpc('admin_execute_sql', {
      sql_query: dataQuery,
    });

    if (error) {
      console.error('[admin/shares] Query error:', error);
      return NextResponse.json(
        { success: false, message: 'Failed to fetch shares' },
        { status: 500 }
      );
    }

    const shares: ShiftShareItem[] = ((data ?? []) as ShiftShareRow[]).map(
      (row) => ({
        id: row.id,
        ownerId: row.owner_id,
        ownerEmail: row.owner_email,
        ownerName: row.owner_name,
        ownerPhone: row.owner_phone,
        viewerId: row.viewer_id,
        viewerEmail: row.viewer_email,
        viewerName: row.viewer_name,
        viewerPhone: row.viewer_phone,
        createdAt: row.created_at,
        showEarnings: row.show_earnings,
        blocked: row.blocked,
        muted: row.muted,
      })
    );

    return NextResponse.json({
      success: true,
      shares,
      totalCount,
      page,
      pageSize,
    });
  } catch (error) {
    console.error('[admin/shares] GET exception:', error);
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * POST /api/admin/shares
 *
 * Create a new shift share between two users.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Body:
 * - ownerId: string - UUID of the shift owner
 * - viewerId: string - UUID of the viewer
 * - showEarnings?: boolean - Whether to show earnings (default: true)
 *
 * Response:
 * - 200: { success: true, id: string }
 * - 400: { success: false, message: string } - Validation error
 * - 401: { success: false, message: string } - Not authenticated or not admin
 * - 500: { success: false, message: string } - Server error
 */
export async function POST(request: NextRequest) {
  try {
    const adminResult = await verifyAdminFromRequest();

    if (!adminResult) {
      return NextResponse.json(
        { success: false, message: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const supabase = createSupabaseServiceClient();
    const adminEmail = adminResult.user.email ?? 'unknown';

    let body: { ownerId?: string; viewerId?: string; showEarnings?: boolean };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { success: false, message: 'Invalid JSON body' },
        { status: 400 }
      );
    }

    const { ownerId, viewerId, showEarnings = true } = body;

    // Validate ownerId
    if (!ownerId) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Missing ownerId',
          intended_action: 'shift_share_created',
        },
      });
      return NextResponse.json(
        { success: false, message: 'Missing required field: ownerId' },
        { status: 400 }
      );
    }

    if (!isValidUUID(ownerId)) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Invalid ownerId format',
          intended_action: 'shift_share_created',
          owner_id: ownerId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Invalid ownerId format' },
        { status: 400 }
      );
    }

    // Validate viewerId
    if (!viewerId) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Missing viewerId',
          intended_action: 'shift_share_created',
        },
      });
      return NextResponse.json(
        { success: false, message: 'Missing required field: viewerId' },
        { status: 400 }
      );
    }

    if (!isValidUUID(viewerId)) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Invalid viewerId format',
          intended_action: 'shift_share_created',
          viewer_id: viewerId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Invalid viewerId format' },
        { status: 400 }
      );
    }

    // Check owner !== viewer
    if (ownerId === viewerId) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Owner and viewer cannot be the same user',
          intended_action: 'shift_share_created',
          owner_id: ownerId,
          viewer_id: viewerId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Owner and viewer cannot be the same user' },
        { status: 400 }
      );
    }

    // Check that both users exist
    const { data: ownerData, error: ownerError } =
      await supabase.auth.admin.getUserById(ownerId);
    if (ownerError || !ownerData?.user) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Owner user not found',
          intended_action: 'shift_share_created',
          owner_id: ownerId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Owner user not found' },
        { status: 400 }
      );
    }

    const { data: viewerData, error: viewerError } =
      await supabase.auth.admin.getUserById(viewerId);
    if (viewerError || !viewerData?.user) {
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: 'Viewer user not found',
          intended_action: 'shift_share_created',
          viewer_id: viewerId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Viewer user not found' },
        { status: 400 }
      );
    }

    const ownerEmail = ownerData.user.email ?? null;
    const viewerEmail = viewerData.user.email ?? null;

    // Insert the shift share
    const { data: insertData, error: insertError } = await supabase
      .from('shift_shares')
      .insert({
        owner_id: ownerId,
        viewer_id: viewerId,
        show_earnings: showEarnings,
        muted: false,
      })
      .select('id')
      .single();

    if (insertError) {
      // Handle unique constraint violation
      if (insertError.code === '23505') {
        await logAdminAction({
          adminId: adminResult.user.id,
          adminEmail,
          action: 'admin_action_failed',
          metadata: {
            error: 'Shift share already exists',
            intended_action: 'shift_share_created',
            owner_id: ownerId,
            owner_email: ownerEmail,
            viewer_id: viewerId,
            viewer_email: viewerEmail,
          },
        });
        return NextResponse.json(
          { success: false, message: 'This share already exists' },
          { status: 400 }
        );
      }

      console.error('[admin/shares] Insert error:', insertError);
      await logAdminAction({
        adminId: adminResult.user.id,
        adminEmail,
        action: 'admin_action_failed',
        metadata: {
          error: insertError.message,
          intended_action: 'shift_share_created',
          owner_id: ownerId,
          viewer_id: viewerId,
        },
      });
      return NextResponse.json(
        { success: false, message: 'Failed to create share' },
        { status: 500 }
      );
    }

    // Log successful action
    await logAdminAction({
      adminId: adminResult.user.id,
      adminEmail,
      action: 'shift_share_created',
      targetId: insertData.id,
      metadata: {
        share_id: insertData.id,
        owner_id: ownerId,
        owner_email: ownerEmail,
        viewer_id: viewerId,
        viewer_email: viewerEmail,
        show_earnings: showEarnings,
      },
    });

    return NextResponse.json({ success: true, id: insertData.id });
  } catch (error) {
    console.error('[admin/shares] POST exception:', error);
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}
