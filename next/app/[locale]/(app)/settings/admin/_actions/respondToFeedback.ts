'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';
import { verifyAdmin } from '@/data-access/auth';
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

  // Verify feedback exists
  const { data: currentFeedback, error: fetchError } = await supabase
    .from('feedback')
    .select('id')
    .eq('id', feedbackId)
    .single();

  if (fetchError || !currentFeedback) {
    logger.error('Failed to fetch feedback:', fetchError);
    throw new Error('Feedback not found');
  }

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

  // Notification is handled by DB trigger (a_on_feedback_responded_notify)

  logger.info('Feedback response submitted:', { feedbackId, adminId: user.id });
  return { success: true };
}
