import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import {
  verifyAdminFromRequest,
  isValidUUID,
} from '../../_lib/verify-admin';
import {
  enqueueDirectNotification,
  generateMutationId,
} from '@/lib/notifications/enqueue';

/**
 * POST /api/admin/feedback/respond
 *
 * Submit or update a response to user feedback.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Body:
 * - feedbackId: string - UUID of the feedback to respond to
 * - response: string - The admin's response (max 2000 characters)
 *
 * Response:
 * - 200: { success: true }
 * - 400: { error: string } - Missing or invalid fields
 * - 401: { error: string } - Not authenticated or not an admin
 * - 404: { error: string } - Feedback not found
 * - 500: { error: string } - Server error
 */

const MAX_RESPONSE_LENGTH = 2000;

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

    // Parse request body
    let body: { feedbackId?: string; response?: string };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { error: 'Invalid JSON body' },
        { status: 400 }
      );
    }

    const { feedbackId, response } = body;

    // Validate feedbackId
    if (!feedbackId || typeof feedbackId !== 'string') {
      return NextResponse.json(
        { error: 'Missing required field: feedbackId' },
        { status: 400 }
      );
    }

    if (!isValidUUID(feedbackId)) {
      return NextResponse.json(
        { error: 'Invalid feedbackId format' },
        { status: 400 }
      );
    }

    // Validate response
    if (!response || typeof response !== 'string') {
      return NextResponse.json(
        { error: 'Missing required field: response' },
        { status: 400 }
      );
    }

    const trimmedResponse = response.trim();

    if (!trimmedResponse) {
      return NextResponse.json(
        { error: 'Response cannot be empty' },
        { status: 400 }
      );
    }

    if (trimmedResponse.length > MAX_RESPONSE_LENGTH) {
      return NextResponse.json(
        { error: `Response must be ${MAX_RESPONSE_LENGTH} characters or less` },
        { status: 400 }
      );
    }

    // Use service client since we've already verified admin access
    const supabase = createSupabaseServiceClient();

    // Get current feedback to check if this is the first response
    const { data: currentFeedback, error: fetchError } = await supabase
      .from('feedback')
      .select('user_id, response')
      .eq('id', feedbackId)
      .single();

    if (fetchError || !currentFeedback) {
      console.error('[admin/feedback/respond] Fetch error:', fetchError);
      return NextResponse.json(
        { error: 'Feedback not found' },
        { status: 404 }
      );
    }

    const isFirstResponse = currentFeedback.response === null;

    // Update the feedback with the response
    const { error: updateError } = await supabase
      .from('feedback')
      .update({
        response: trimmedResponse,
        responded_at: new Date().toISOString(),
        responded_by: adminResult.user.id,
      })
      .eq('id', feedbackId);

    if (updateError) {
      console.error('[admin/feedback/respond] Update error:', updateError);
      return NextResponse.json(
        { error: 'Failed to submit response' },
        { status: 500 }
      );
    }

    // Only send notification on first response (not edits)
    if (isFirstResponse) {
      try {
        const mutationId = generateMutationId();

        await enqueueDirectNotification({
          recipientId: currentFeedback.user_id,
          senderId: adminResult.user.id,
          notificationType: 'feedback_responded',
          title: 'Svar på tilbakemeldingen din',
          body: `${trimmedResponse.slice(0, 100)}${trimmedResponse.length > 100 ? '...' : ''}`,
          dataPayload: {
            type: 'feedback_responded',
            feedback_id: feedbackId,
            response_preview: trimmedResponse.slice(0, 150),
          },
          idempotencyKey: `feedback_responded:${feedbackId}:${mutationId}`,
        });
      } catch (notificationError) {
        // Log but don't fail the request if notification fails
        console.error(
          '[admin/feedback/respond] Notification error:',
          notificationError
        );
      }
    }

    console.info('[admin/feedback/respond] Response submitted:', {
      feedbackId,
      adminId: adminResult.user.id,
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('[admin/feedback/respond] Exception:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
