import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { getSession } from '@/data-access/auth';
import { createSupabaseServiceClient } from '@/lib/supabase/service';

type TargetAudience = 'all' | 'pro' | 'active' | 'specific';

interface PreviewTargetBody {
  target: TargetAudience;
  specificUserId?: string; // Legacy single user
  specificUserIds?: string[]; // Multiple users
  includeSelf?: boolean;
}

/**
 * POST /api/admin/notifications/preview
 *
 * Returns the count of users that would be targeted by a broadcast.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 *
 * Authorization:
 * - User must have admin role in app_metadata
 *
 * Body:
 * - target: 'all' | 'pro' | 'active' | 'specific' - Target audience
 * - specificUserId?: string - Required if target is 'specific'
 * - includeSelf?: boolean - Include sending admin in count
 *
 * Response:
 * - 200: { count: number }
 * - 400: { error: string } - Validation error
 * - 401: { error: string } - Not authenticated
 * - 403: { error: string } - Not authorized (not admin)
 * - 500: { error: string } - Server error
 */
export async function POST(request: NextRequest) {
  try {
    let userId: string | null = null;
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
        userAppMetadata = user.app_metadata ?? {};
      }
    }

    // 2. Fall back to cookie session (web app)
    if (!userId) {
      const session = await getSession();
      if (session) {
        userId = session.user.id;
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
    const input: PreviewTargetBody = await request.json();

    // Validate target
    if (!['all', 'pro', 'active', 'specific'].includes(input.target)) {
      return NextResponse.json(
        { error: 'Invalid target. Must be all, pro, active, or specific' },
        { status: 400 }
      );
    }

    // Handle specific user targeting
    if (input.target === 'specific') {
      const userIds = input.specificUserIds ?? (input.specificUserId ? [input.specificUserId] : []);
      // Return count of selected users
      return NextResponse.json({ count: userIds.length });
    }

    // Service role client for admin operations
    const supabase = createSupabaseServiceClient();

    let rpcName: string;
    let rpcParams: Record<string, unknown> = {};

    switch (input.target) {
      case 'pro':
        rpcName = 'admin_count_target_users_pro';
        break;
      case 'active':
        rpcName = 'admin_count_target_users_active';
        break;
      default: // 'all'
        rpcName = 'admin_count_target_users_all';
        rpcParams = { exclude_user_id: input.includeSelf ? null : userId };
    }

    const { data, error } = await supabase.rpc(rpcName, rpcParams);

    if (error) {
      console.error('[admin/notifications/preview] RPC error:', error);
      return NextResponse.json(
        { error: 'Failed to get target count' },
        { status: 500 }
      );
    }

    // COUNT functions return BIGINT directly
    return NextResponse.json({ count: Number(data) || 0 });
  } catch (error) {
    console.error('[admin/notifications/preview] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
