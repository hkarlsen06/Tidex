import { NextResponse } from 'next/server';
import { getSession } from '@/data-access/auth';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { isNextInternalError } from '../../_lib/verify-admin';

/**
 * Broadcast record as returned from the database
 */
interface BroadcastRecordDB {
  id: string;
  title: string;
  body: string;
  target: string;
  target_count: number;
  status: string;
  created_at: string;
  sent_count: number;
  failed_count: number;
  skipped_count: number;
  pending_count: number;
}

/**
 * Broadcast record with camelCase keys for Swift Codable
 */
interface BroadcastRecord {
  id: string;
  title: string;
  body: string;
  target: string;
  targetCount: number;
  status: string;
  createdAt: string;
  sentCount: number;
  failedCount: number;
  skippedCount: number;
  pendingCount: number;
}

/**
 * GET /api/admin/notifications/history
 *
 * Returns the broadcast notification history for admin users.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 *
 * Authorization:
 * - User must have admin role in app_metadata
 *
 * Response:
 * - 200: { broadcasts: BroadcastRecord[] }
 * - 401: { error: string } - Not authenticated
 * - 403: { error: string } - Not authorized (not admin)
 * - 500: { error: string } - Server error
 */
export async function GET() {
  try {
    // getSession handles both Bearer tokens (iOS) and cookies (web)
    const session = await getSession();
    if (!session) {
      return NextResponse.json({ error: 'Not authenticated' }, { status: 401 });
    }

    // Verify admin role
    const isAdmin = (session.user.app_metadata?.role as string) === 'admin';
    if (!isAdmin) {
      return NextResponse.json({ error: 'Access denied' }, { status: 403 });
    }

    // Service role client to call admin RPC
    const supabase = createSupabaseServiceClient();

    const { data, error } = await supabase.rpc('admin_get_broadcast_history', {
      limit_count: 10,
    });

    if (error) {
      console.error('[admin/notifications/history] RPC error:', error);
      return NextResponse.json(
        { error: 'Failed to fetch broadcast history' },
        { status: 500 }
      );
    }

    // Transform snake_case to camelCase for Swift Codable compatibility
    const broadcasts: BroadcastRecord[] = ((data as BroadcastRecordDB[]) || []).map((record) => ({
      id: record.id,
      title: record.title,
      body: record.body,
      target: record.target,
      targetCount: record.target_count,
      status: record.status,
      createdAt: record.created_at,
      sentCount: record.sent_count,
      failedCount: record.failed_count,
      skippedCount: record.skipped_count,
      pendingCount: record.pending_count,
    }));

    return NextResponse.json(
      { broadcasts },
      {
        headers: {
          'Cache-Control': 'private, max-age=30, stale-while-revalidate=10',
        },
      }
    );
  } catch (error) {
    // Re-throw Next.js internal errors (prerender bailout, etc.)
    if (isNextInternalError(error)) throw error;
    console.error('[admin/notifications/history] Error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
