'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';
import { verifyAdmin } from '@/data-access/auth';
import {
  enqueueDirectNotification,
  generateMutationId,
} from '@/lib/notifications/enqueue';

const MAX_RESPONSE_LENGTH = 2000;

export async function respondToFeedback(
  feedbackId: string,
  response: string
): Promise<{ success: boolean }> {
  const { user } = await verifyAdmin();
  const supabase = await createSupabaseServerClient();

  // Validate response
  const trimmedResponse = response.trim();

  if (!trimmedResponse) {
    throw new Error('Response cannot be empty');
  }

  if (trimmedResponse.length > MAX_RESPONSE_LENGTH) {
    throw new Error(`Response must be ${MAX_RESPONSE_LENGTH} characters or less`);
  }

  // Get current feedback to check if this is the first response
  const { data: currentFeedback, error: fetchError } = await supabase
    .from('feedback')
    .select('user_id, response')
    .eq('id', feedbackId)
    .single();

  if (fetchError || !currentFeedback) {
    logger.error('Failed to fetch feedback:', fetchError);
    throw new Error('Feedback not found');
  }

  const isFirstResponse = currentFeedback.response === null;

  const { error } = await supabase
    .from('feedback')
    .update({
      response: trimmedResponse,
      responded_at: new Date().toISOString(),
      responded_by: user.id,
    })
    .eq('id', feedbackId);

  if (error) {
    logger.error('Failed to respond to feedback:', error);
    throw new Error('Failed to submit response');
  }

  // Only send notification on first response (not edits)
  if (isFirstResponse) {
    const mutationId = generateMutationId();

    await enqueueDirectNotification({
      recipientId: currentFeedback.user_id,
      senderId: user.id,
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
  }

  logger.info('Feedback response submitted:', { feedbackId, adminId: user.id });
  return { success: true };
}
