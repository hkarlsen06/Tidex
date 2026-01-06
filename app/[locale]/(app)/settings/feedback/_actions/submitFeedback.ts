'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';
import { verifySession } from '@/data-access/auth';
import {
  enqueueDirectNotification,
  generateMutationId,
  getOwnerName,
} from '@/lib/notifications/enqueue';

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

  const { data: insertedFeedback, error } = await supabase.from('feedback').insert({
    user_id: user.id,
    message: trimmedMessage,
    user_email: user.email ?? 'unknown',
  }).select('id').single();

  if (error) {
    logger.error('Failed to submit feedback:', error);
    throw new Error('Failed to submit feedback');
  }

  // Get all admin users to notify
  const { data: admins } = await supabase.rpc('get_admin_user_ids');

  if (admins && admins.length > 0) {
    const mutationId = generateMutationId();
    const userName = getOwnerName(user);

    // Enqueue notifications for each admin
    await Promise.all(
      admins.map((adminId: string) =>
        enqueueDirectNotification({
          recipientId: adminId,
          senderId: user.id,
          notificationType: 'feedback_submitted',
          title: 'Ny tilbakemelding',
          body: `${userName}: ${trimmedMessage.slice(0, 100)}${trimmedMessage.length > 100 ? '...' : ''}`,
          dataPayload: {
            type: 'feedback_submitted',
            feedback_id: insertedFeedback.id,
            user_name: userName,
            user_email: user.email ?? 'unknown',
          },
          idempotencyKey: `feedback:${insertedFeedback.id}:${adminId}:${mutationId}`,
        })
      )
    );
  }

  logger.info('Feedback submitted:', { userId: user.id });
  return { success: true };
}
