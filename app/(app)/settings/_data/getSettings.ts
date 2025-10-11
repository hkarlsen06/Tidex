'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function getUserSettings(userId: string) {
  try {
    const supabase = await createSupabaseServerClient();

    const { data, error } = await supabase
      .from('user_settings')
      .select('*')
      .eq('user_id', userId)
      .single();

    if (error) {
      logger.error('Failed to fetch user settings:', error);
      return null;
    }
    return data;
  } catch (error) {
    logger.error('Unexpected error fetching settings:', error);
    return null;
  }
}

export async function getUserProfile() {
  const supabase = await createSupabaseServerClient();

  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  // Get settings for profile picture
  const { data: settings } = await supabase
    .from('user_settings')
    .select('profile_picture_url')
    .eq('user_id', user.id)
    .single();

  // Check if user has Google OAuth connected
  const hasGoogleConnected = user.identities?.some(
    (identity) => identity.provider === 'google'
  ) ?? false;

  return {
    firstName: user.user_metadata?.first_name || '',
    email: user.email || '',
    profilePictureUrl: settings?.profile_picture_url || null,
    hasGoogleConnected,
  };
}
