'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';
import { verifySession } from '@/data-access/auth';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';

export async function updateProfileSettings(data: {
  firstName: string;
  profilePictureUrl?: string | null;
}) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

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

  invalidateAndRevalidate(user.id);
  return { success: true };
}

export async function clearAllShifts() {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const { error } = await supabase
    .from('user_shifts')
    .delete()
    .eq('user_id', user.id);

  if (error) throw error;

  // Invalidate cache since all shifts were deleted - critical for consistency
  invalidateAndRevalidate(user.id);
  return { success: true };
}

export async function updatePaySettings(data: {
  monthly_goal?: number | null;
  payroll_day?: number | null;
  pause_deduction_enabled?: boolean;
  pause_deduction_method?: string | null;
  pause_threshold_hours?: number | null;
  pause_deduction_minutes?: number | null;
  tax_deduction_enabled?: boolean;
  tax_percentage?: number | null;
  half_tax_month?: number | null;
}) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const { error } = await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  if (error) {
    logger.error('Failed to update pay settings:', error);
    throw error;
  }

  // Invalidate cache and revalidate all pages since tax settings affect home page
  invalidateAndRevalidate(user.id);
  return { success: true };
}

export async function updateDisplaySettings(data: {
  theme?: string;
  default_shifts_view?: string;
}) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const { error } = await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  if (error) {
    logger.error('Failed to update display settings:', error);
    throw error;
  }

  invalidateAndRevalidate(user.id);
  return { success: true };
}

export async function updatePreferencesSettings(data: {
  direct_time_input?: boolean;
  full_minute_range?: boolean;
}) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient(); // Still needed for DB operations

  const { error } = await supabase
    .from('user_settings')
    .update(data)
    .eq('user_id', user.id);

  if (error) {
    logger.error('Failed to update preferences settings:', error);
    throw error;
  }

  invalidateAndRevalidate(user.id);
  return { success: true };
}

export async function connectGoogleAccount(redirectUrl: string) {
  await verifySession();
  const supabase = await createSupabaseServerClient();

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
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Find Google identity
  const googleIdentity = user.identities?.find(
    (identity: { provider: string }) => identity.provider === 'google'
  );

  if (!googleIdentity) {
    throw new Error('Ingen Google-konto funnet');
  }

  logger.info('Unlinking Google identity:', {
    identityId: googleIdentity.identity_id,
    provider: googleIdentity.provider,
    userId: user.id,
  });

  // Unlink the identity - pass the whole identity object
  const { error } = await supabase.auth.unlinkIdentity(googleIdentity);

  if (error) {
    logger.error('Failed to unlink Google identity:', error);
    throw error;
  }

  invalidateAndRevalidate(user.id);
  return { success: true };
}

export async function linkPhoneNumber(phone: string) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Store the pending phone number in user metadata and send OTP
  // We don't use updateUser({ phone }) directly because it might not require confirmation
  // depending on Supabase project settings
  const existingMetadata = user.user_metadata ?? {};

  // First, store the pending phone in metadata (not the actual phone field yet)
  const { error: metadataError } = await supabase.auth.updateUser({
    data: {
      ...existingMetadata,
      pendingPhone: phone,
    },
  });

  if (metadataError) {
    logger.error('Failed to store pending phone:', metadataError);
    throw metadataError;
  }

  // Now send the OTP using signInWithOtp in a way that doesn't create a new session
  // We use the phone provider but with the current user's session
  const { error } = await supabase.auth.updateUser({
    phone,
  });

  if (error) {
    logger.error('Failed to initiate phone linking:', error);
    throw error;
  }

  logger.info('OTP sent for phone linking:', { phone });
  return { success: true };
}

export async function verifyAndLinkPhone(phone: string, otp: string) {
  const { user: currentUser } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Verify that this phone matches the pending phone
  const pendingPhone = currentUser.user_metadata?.pendingPhone;
  if (pendingPhone !== phone) {
    throw new Error('Phone number mismatch');
  }

  // Verify the OTP for phone change
  const { data, error: verifyError } = await supabase.auth.verifyOtp({
    phone,
    token: otp,
    type: 'phone_change',
  });

  if (verifyError) {
    logger.error('Failed to verify OTP:', verifyError);
    throw verifyError;
  }

  if (!data.user) {
    throw new Error('Verification failed');
  }

  // Check that phone was actually confirmed
  if (!data.user.phone_confirmed_at) {
    logger.error('Phone not confirmed after OTP verification');
    throw new Error('Phone verification incomplete');
  }

  // Clean up pending phone from metadata
  const existingMetadata = data.user.user_metadata ?? {};
  const { pendingPhone: _, ...cleanedMetadata } = existingMetadata;

  await supabase.auth.updateUser({
    data: cleanedMetadata,
  });

  logger.info('Phone number successfully linked and confirmed:', {
    userId: data.user.id,
    phone: phone,
    confirmedAt: data.user.phone_confirmed_at,
  });

  invalidateAndRevalidate(data.user.id);
  return { success: true };
}

export async function unlinkPhoneNumber() {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Find phone identity
  const phoneIdentity = user.identities?.find(
    (identity: { provider: string }) => identity.provider === 'phone'
  );

  if (!phoneIdentity) {
    throw new Error('Ingen telefonnummer funnet');
  }

  logger.info('Unlinking phone identity:', {
    identityId: phoneIdentity.identity_id,
    provider: phoneIdentity.provider,
    userId: user.id,
  });

  // Unlink the identity
  const { error } = await supabase.auth.unlinkIdentity(phoneIdentity);

  if (error) {
    logger.error('Failed to unlink phone identity:', error);
    throw error;
  }

  invalidateAndRevalidate(user.id);
  return { success: true };
}

/**
 * Request reauthentication OTP for phone-only users
 * This is required before they can set/update their password
 */
export async function requestReauthentication() {
  await verifySession();
  const supabase = await createSupabaseServerClient();

  const { error } = await supabase.auth.reauthenticate();

  if (error) {
    logger.error('Failed to request reauthentication:', error);
    throw error;
  }

  return { success: true };
}

/**
 * Set or update user password
 * For phone-only users, nonce (OTP) is required after calling requestReauthentication()
 */
export async function setPassword(password: string, nonce?: string) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Validate password length
  if (password.length < 6) {
    throw new Error('Passordet må være minst 6 tegn langt');
  }

  // Update user password (with nonce if provided for phone-only users)
  const updateData: { password: string; nonce?: string } = { password };
  if (nonce) {
    updateData.nonce = nonce;
  }

  const { error } = await supabase.auth.updateUser(updateData);

  if (error) {
    logger.error('Failed to set password:', error);
    throw error;
  }

  // Note: Password change doesn't modify user_settings, but we revalidate
  // to ensure auth state is refreshed across the app
  invalidateAndRevalidate(user.id);
  return { success: true };
}

export async function initiateEmailChange(newEmail: string) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Validate email format
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(newEmail)) {
    throw new Error('Ugyldig e-postadresse');
  }

  // Check if new email is same as current
  if (user.email === newEmail) {
    throw new Error('Den nye e-postadressen er den samme som den nåværende');
  }

  // Store the pending email in user metadata and initiate email change
  const existingMetadata = user.user_metadata ?? {};

  // Initiate email change - Supabase will send a confirmation email
  // The user needs to click the link in BOTH the old and new email
  const { error } = await supabase.auth.updateUser({
    email: newEmail,
    data: {
      ...existingMetadata,
      pendingEmail: newEmail,
    },
  });

  if (error) {
    logger.error('Failed to initiate email change:', error);
    throw error;
  }

  logger.info('Email change initiated:', { newEmail });
  return { success: true };
}

