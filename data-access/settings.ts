'use server';

import { verifySession } from '@/data-access/auth';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

/**
 * Get user settings for the authenticated user
 * - Automatically verifies user session matches provided userId
 */
export async function getUserSettings(userId: string) {
  try {
    const { user } = await verifySession();

    // SECURITY: Verify the provided userId matches the authenticated user
    if (user.id !== userId) {
      throw new Error('User ID mismatch - potential security violation');
    }

    const supabase = await createSupabaseServerClient();

    const { data, error } = await supabase
      .from('user_settings')
      .select('*')
      .eq('user_id', user.id)
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

/**
 * Get user profile information including authentication methods
 * - Automatically verifies user session matches provided userId
 */
export async function getUserProfile(userId: string) {
  const { user } = await verifySession();

  // SECURITY: Verify the provided userId matches the authenticated user
  if (user.id !== userId) {
    throw new Error('User ID mismatch - potential security violation');
  }

  const supabase = await createSupabaseServerClient();

  // Get settings for profile picture
  const { data: settings } = await supabase
    .from('user_settings')
    .select('profile_picture_url')
    .eq('user_id', user.id)
    .single();

  const identityProviders = new Set(
    user.identities?.map((identity) => identity.provider) ?? []
  );

  // Check if user has Google OAuth connected
  const hasGoogleConnected = identityProviders.has('google');

  // Check if user has phone number linked
  const hasPhoneConnected = identityProviders.has('phone');

  // Get phone number and strip +47 prefix for display
  let phoneNumber: string | null = null;
  if (user.phone) {
    phoneNumber = user.phone.startsWith('+47')
      ? user.phone.substring(3)
      : user.phone;
  }

  // Check if user has a password set
  // Users have password if they signed up with email or have set one later
  const hasPassword = identityProviders.has('email');

  const loginMethodCount = identityProviders.size;
  const canUnlinkPhone = hasPhoneConnected && loginMethodCount > 1;
  const canDisconnectGoogle = hasGoogleConnected && loginMethodCount > 1;

  return {
    firstName: user.user_metadata?.first_name || '',
    email: user.email || '',
    profilePictureUrl: settings?.profile_picture_url || null,
    hasGoogleConnected,
    hasPhoneConnected,
    phoneNumber,
    hasPassword,
    canUnlinkPhone,
    canDisconnectGoogle,
  };
}
