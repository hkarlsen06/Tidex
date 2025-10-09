'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function getUserSettings(userId: string) {
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from('user_settings')
    .select('*')
    .eq('user_id', userId)
    .single();

  if (error) throw error;
  return data;
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

  return {
    firstName: user.user_metadata?.first_name || '',
    email: user.email || '',
    profilePictureUrl: settings?.profile_picture_url || null,
  };
}
