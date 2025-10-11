'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { logger } from '@/lib/logger';

// Validation schema for bonus rules
const BonusRuleSchema = z.object({
  days: z.array(z.number().int().min(1).max(7)),
  from: z.string().regex(/^\d{2}:\d{2}$/),
  to: z.string().regex(/^\d{2}:\d{2}$/),
  rate: z.number().optional(),
  percent: z.number().optional(),
});

const CustomBonusesSchema = z.object({
  rules: z.array(BonusRuleSchema),
});

export async function updateProfileSettings(data: {
  firstName: string;
  profilePictureUrl?: string | null;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  // Update auth metadata
  const existingMetadata = user.user_metadata ?? {};

  await supabase.auth.updateUser({
    data: {
      ...existingMetadata,
      first_name: data.firstName,
    },
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

  // Only revalidate shifts page since that's what changed
  revalidatePath('/shifts');
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

  // Validate custom_bonuses if provided
  if (data.custom_bonuses !== undefined && data.custom_bonuses !== null) {
    try {
      CustomBonusesSchema.parse(data.custom_bonuses);
    } catch (error) {
      logger.error('Invalid custom_bonuses format:', error);
      throw new Error('Ugyldig bonuskonfigurasjon');
    }
  }

  const { error } = await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  if (error) {
    logger.error('Failed to update pay settings:', error);
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
    logger.error('Failed to update display settings:', error);
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
    logger.error('Failed to update preferences settings:', error);
    throw error;
  }

  revalidatePath('/settings/preferences');
  return { success: true };
}

export async function connectGoogleAccount(redirectUrl: string) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  // linkIdentity returns a URL that the client needs to navigate to
  const { data, error } = await supabase.auth.linkIdentity({
    provider: 'google',
    options: {
      redirectTo: redirectUrl,
      queryParams: {
        access_type: 'offline',
        prompt: 'consent',
      },
    },
  });

  if (error) {
    logger.error('Failed to link Google identity:', error);
    throw error;
  }

  // Return the OAuth URL for the client to navigate to
  return { url: data.url };
}

export async function disconnectGoogleAccount() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) throw new Error('Not authenticated');

  // Find Google identity
  const googleIdentity = user.identities?.find(
    (identity) => identity.provider === 'google'
  );

  if (!googleIdentity) {
    throw new Error('Ingen Google-konto funnet');
  }

  logger.info('Unlinking Google identity:', {
    identityId: googleIdentity.identity_id,
    provider: googleIdentity.provider,
    userId: user.id,
  });

  // Unlink the identity - use identity_id field, not id
  const { error } = await supabase.auth.unlinkIdentity({
    identity_id: googleIdentity.identity_id || googleIdentity.id,
  });

  if (error) {
    logger.error('Failed to unlink Google identity:', error);
    throw error;
  }

  revalidatePath('/settings/profile');
  return { success: true };
}
