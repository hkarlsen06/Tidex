'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';
import { verifySession } from '@/data-access/auth';

export interface UserFeedbackItem {
  id: string;
  message: string;
  created_at: string;
  response: string | null;
  responded_at: string | null;
}

export async function getUserFeedback(): Promise<UserFeedbackItem[]> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from('feedback')
    .select('id, message, created_at, response, responded_at')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });

  if (error) {
    logger.error('Failed to fetch user feedback:', error);
    throw new Error('Failed to fetch feedback history');
  }

  return (data ?? []) as UserFeedbackItem[];
}
