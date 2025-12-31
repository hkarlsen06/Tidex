'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { logger } from '@/lib/logger';
import { verifyAdmin } from '@/data-access/auth';

export interface FeedbackItem {
  id: string;
  user_id: string;
  message: string;
  user_email: string;
  user_name: string | null;
  user_profile_picture: string | null;
  created_at: string;
  response: string | null;
  responded_at: string | null;
  responded_by: string | null;
}

export async function getFeedback(limit = 20, offset = 0): Promise<{
  feedback: FeedbackItem[];
  total: number;
}> {
  await verifyAdmin();
  const supabase = await createSupabaseServerClient();
  const serviceClient = createSupabaseServiceClient();

  const { data, count, error } = await supabase
    .from('feedback')
    .select('*', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (error) {
    logger.error('Failed to fetch feedback:', error);
    throw new Error('Failed to fetch feedback');
  }

  // Fetch user names and profile pictures
  const userIds = [...new Set((data ?? []).map((f) => f.user_id))];
  const userNames: Record<string, string | null> = {};
  const userProfilePictures: Record<string, string | null> = {};

  if (userIds.length > 0) {
    // Fetch users from auth
    const { data: authData } = await serviceClient.auth.admin.listUsers({
      perPage: 1000,
    });

    if (authData?.users) {
      for (const user of authData.users) {
        if (userIds.includes(user.id)) {
          userNames[user.id] = (user.user_metadata?.full_name as string) ?? null;
        }
      }
    }

    // Fetch profile pictures from user_settings
    const { data: settingsData } = await supabase
      .from('user_settings')
      .select('user_id, profile_picture_url')
      .in('user_id', userIds);

    if (settingsData) {
      for (const setting of settingsData) {
        userProfilePictures[setting.user_id] = setting.profile_picture_url ?? null;
      }
    }
  }

  const feedbackWithNames = (data ?? []).map((item) => ({
    ...item,
    user_name: userNames[item.user_id] ?? null,
    user_profile_picture: userProfilePictures[item.user_id] ?? null,
  })) as FeedbackItem[];

  return {
    feedback: feedbackWithNames,
    total: count ?? 0,
  };
}
