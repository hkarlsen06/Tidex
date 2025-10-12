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

  // Check if user has phone number linked
  const hasPhoneConnected = user.identities?.some(
    (identity) => identity.provider === 'phone'
  ) ?? false;

  // Get phone number and strip +47 prefix for display
  let phoneNumber: string | null = null;
  if (user.phone) {
    phoneNumber = user.phone.startsWith('+47')
      ? user.phone.substring(3)
      : user.phone;
  }

  // Check if user has a password set
  // Users have password if they signed up with email or have set one later
  const hasPassword = user.identities?.some(
    (identity) => identity.provider === 'email'
  ) ?? false;

  return {
    firstName: user.user_metadata?.first_name || '',
    email: user.email || '',
    profilePictureUrl: settings?.profile_picture_url || null,
    hasGoogleConnected,
    hasPhoneConnected,
    phoneNumber,
    hasPassword,
  };
}
