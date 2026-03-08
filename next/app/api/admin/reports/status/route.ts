import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import {
  verifyAdminFromRequest,
  isValidUUID,
  isNextInternalError,
} from '../../_lib/verify-admin';

const VALID_STATUSES = ['open', 'in_review', 'actioned', 'dismissed'] as const;
const MAX_NOTES_LENGTH = 2000;

export async function POST(request: NextRequest) {
  try {
    const adminResult = await verifyAdminFromRequest();

    if (!adminResult) {
      return NextResponse.json(
        { error: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    let body: { reportId?: string; status?: string; reviewerNotes?: string | null };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
    }

    const { reportId, status, reviewerNotes } = body;

    if (!reportId || typeof reportId !== 'string' || !isValidUUID(reportId)) {
      return NextResponse.json({ error: 'Invalid reportId' }, { status: 400 });
    }

    if (!status || !VALID_STATUSES.includes(status as (typeof VALID_STATUSES)[number])) {
      return NextResponse.json({ error: 'Invalid status' }, { status: 400 });
    }

    const normalizedNotes = reviewerNotes?.trim() || null;
    if (normalizedNotes && normalizedNotes.length > MAX_NOTES_LENGTH) {
      return NextResponse.json(
        { error: `Reviewer notes must be ${MAX_NOTES_LENGTH} characters or less` },
        { status: 400 }
      );
    }

    const serviceClient = createSupabaseServiceClient();
    const { error } = await serviceClient
      .from('abuse_reports')
      .update({
        status,
        reviewer_notes: normalizedNotes,
        reviewed_at: new Date().toISOString(),
        reviewed_by: adminResult.user.id,
      })
      .eq('id', reportId);

    if (error) {
      console.error('[admin/reports/status] Update error:', error);
      return NextResponse.json(
        { error: 'Failed to update report' },
        { status: 500 }
      );
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    if (isNextInternalError(error)) throw error;
    console.error('[admin/reports/status] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
