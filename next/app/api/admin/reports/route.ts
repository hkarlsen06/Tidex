import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { verifyAdminFromRequest, isNextInternalError } from '../_lib/verify-admin';

interface ReportItem {
  id: string;
  reporterUserId: string;
  reporterName: string | null;
  reporterEmail: string | null;
  reportedUserId: string;
  reportedName: string | null;
  reportedEmail: string | null;
  threadId: string;
  messageId: string | null;
  reason: string;
  note: string | null;
  status: string;
  reviewerNotes: string | null;
  reviewedAt: string | null;
  reviewedBy: string | null;
  createdAt: string;
}

export async function GET(request: NextRequest) {
  try {
    const adminResult = await verifyAdminFromRequest();

    if (!adminResult) {
      return NextResponse.json(
        { error: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const serviceClient = createSupabaseServiceClient();
    const searchParams = request.nextUrl.searchParams;
    const limit = Math.max(
      1,
      Math.min(100, parseInt(searchParams.get('limit') ?? '20', 10))
    );
    const offset = Math.max(0, parseInt(searchParams.get('offset') ?? '0', 10));
    const status = searchParams.get('status');

    let query = serviceClient
      .from('abuse_reports')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (status && ['open', 'in_review', 'actioned', 'dismissed'].includes(status)) {
      query = query.eq('status', status);
    }

    const { data, count, error } = await query;

    if (error) {
      console.error('[admin/reports] Fetch error:', error);
      return NextResponse.json(
        { error: 'Failed to fetch reports' },
        { status: 500 }
      );
    }

    const userIds = [...new Set((data ?? []).flatMap((item) => [item.reporter_user_id, item.reported_user_id]))];
    const userDirectory = new Map<string, { name: string | null; email: string | null }>();

    if (userIds.length > 0) {
      const { data: authData } = await serviceClient.auth.admin.listUsers({ perPage: 1000 });
      for (const user of authData?.users ?? []) {
        if (userIds.includes(user.id)) {
          userDirectory.set(user.id, {
            name: (user.user_metadata?.full_name as string | undefined)
              ?? (user.user_metadata?.name as string | undefined)
              ?? null,
            email: user.email ?? null,
          });
        }
      }
    }

    const reports: ReportItem[] = (data ?? []).map((item) => ({
      id: item.id,
      reporterUserId: item.reporter_user_id,
      reporterName: userDirectory.get(item.reporter_user_id)?.name ?? null,
      reporterEmail: userDirectory.get(item.reporter_user_id)?.email ?? null,
      reportedUserId: item.reported_user_id,
      reportedName: userDirectory.get(item.reported_user_id)?.name ?? null,
      reportedEmail: userDirectory.get(item.reported_user_id)?.email ?? null,
      threadId: item.thread_id,
      messageId: item.message_id,
      reason: item.reason,
      note: item.note,
      status: item.status,
      reviewerNotes: item.reviewer_notes,
      reviewedAt: item.reviewed_at,
      reviewedBy: item.reviewed_by,
      createdAt: item.created_at,
    }));

    return NextResponse.json({
      reports,
      total: count ?? 0,
    });
  } catch (error) {
    if (isNextInternalError(error)) throw error;
    console.error('[admin/reports] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
