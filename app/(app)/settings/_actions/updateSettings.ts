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
  current_wage_level?: number;
  custom_wage?: number;
  custom_bonuses?: any;
  monthly_goal?: number;
  payroll_day?: number;
  pause_deduction_enabled?: boolean;
  pause_deduction_method?: string;
  pause_threshold_hours?: number;
  pause_deduction_minutes?: number;
  tax_deduction_enabled?: boolean;
  tax_percentage?: number;
  break_policy?: string;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  revalidatePath('/settings/pay');
  return { success: true };
}

export async function updateDisplaySettings(data: {
  theme?: string;
  default_shifts_view?: string;
  currency_format?: string;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  revalidatePath('/settings/display');
  return { success: true };
}

export async function updatePreferencesSettings(data: {
  show_employee_tab?: boolean;
  direct_time_input?: boolean;
  full_minute_range?: boolean;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  revalidatePath('/settings/preferences');
  return { success: true };
}
