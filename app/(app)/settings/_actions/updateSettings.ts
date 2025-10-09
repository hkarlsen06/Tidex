'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';

export async function updateProfileSettings(data: {
  firstName: string;
  profilePictureUrl?: string | null;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  // Update auth metadata
  await supabase.auth.updateUser({
    data: { first_name: data.firstName }
  });

  // Update profile picture if changed
  if (data.profilePictureUrl !== undefined) {
    await supabase
      .from('user_settings')
      .update({ profile_picture_url: data.profilePictureUrl })
      .eq('user_id', user.id);
  }

  revalidatePath('/settings/profile');
  return { success: true };
}

export async function clearAllShifts() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  const { error } = await supabase
    .from('user_shifts')
    .delete()
    .eq('user_id', user.id);

  if (error) throw error;

  revalidatePath('/shifts');
  revalidatePath('/settings/profile');
  return { success: true };
}

export async function updatePaySettings(data: {
  use_preset?: boolean;
  current_wage_level?: number | null;
  custom_wage?: number | null;
  custom_bonuses?: any;
  monthly_goal?: number | null;
  payroll_day?: number | null;
  pause_deduction_enabled?: boolean;
  pause_deduction_method?: string | null;
  pause_threshold_hours?: number | null;
  pause_deduction_minutes?: number | null;
  tax_deduction_enabled?: boolean;
  tax_percentage?: number | null;
  break_policy?: string;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  const { error } = await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  if (error) {
    console.error('Failed to update pay settings:', error);
    throw error;
  }

  revalidatePath('/settings/pay');
  return { success: true };
}

export async function updateDisplaySettings(data: {
  theme?: string;
  default_shifts_view?: string;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  const { error } = await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  if (error) {
    console.error('Failed to update display settings:', error);
    throw error;
  }

  revalidatePath('/settings/display');
  return { success: true };
}

export async function updatePreferencesSettings(data: {
  direct_time_input?: boolean;
  full_minute_range?: boolean;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  const { error } = await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  if (error) {
    console.error('Failed to update preferences settings:', error);
    throw error;
  }

  revalidatePath('/settings/preferences');
  return { success: true };
}
