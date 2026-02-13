'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';
import { verifySession } from '@/data-access/auth';

const MAX_FEEDBACK_LENGTH = 2000;

export async function submitFeedback(message: string) {
  const { user } = await verifySession();

  // Validate message
  const trimmedMessage = message.trim();

  if (!trimmedMessage) {
    throw new Error('Feedback cannot be empty');
  }

  if (trimmedMessage.length > MAX_FEEDBACK_LENGTH) {
    throw new Error(`Feedback must be ${MAX_FEEDBACK_LENGTH} characters or less`);
  }

  const supabase = await createSupabaseServerClient();

  // Admin notifications are handled by the database trigger
  // (queue_feedback_submitted_notification) on INSERT
  const { error } = await supabase.from('feedback').insert({
    user_id: user.id,
    message: trimmedMessage,
    user_email: user.email ?? 'unknown',
  });

  if (error) {
    logger.error('Failed to submit feedback:', error);
    throw new Error('Failed to submit feedback');
  }

  logger.info('Feedback submitted:', { userId: user.id });
  return { success: true };
}
