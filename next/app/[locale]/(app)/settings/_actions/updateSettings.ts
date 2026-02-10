'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { logger } from '@/lib/logger';
import { verifySession } from '@/data-access/auth';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';
import { enforceNotImpersonating } from '@/lib/auth/impersonation';

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
      full_name: data.firstName,
    },
  });

  // Note: We don't call refreshSession() here because server-side cookie updates
  // race with router.refresh(). Instead, the client calls refreshSession() after
  // this action returns, which updates cookies client-side and triggers
  // SupabaseListener to call router.refresh() with the new JWT.

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

  // Soft delete all shifts by setting deleted_at
  const { error } = await supabase
    .from('user_shifts')
    .update({ deleted_at: new Date().toISOString() })
    .eq('user_id', user.id)
    .is('deleted_at', null); // Only delete non-deleted shifts

  if (error) throw error;

  // Invalidate cache since all shifts were deleted - critical for consistency
  invalidateAndRevalidate(user.id);
  return { success: true };
}

/**
 * Update global pay settings
 *
 * NOTE: Tax and break deduction settings have been moved to wage_snapshots.
 * This function now only handles global calendar preferences:
 * - monthly_goal: Earnings target for the month
 * - payroll_day: Day of month when payroll is received
 * - half_tax_month: Month number for half tax deduction (11=Nov, 12=Dec)
 */
export async function updatePaySettings(data: {
  monthly_goal?: number | null;
  payroll_day?: number | null;
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
  currency?: string;
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
  // verifySession() uses getClaims() which parses the JWT locally.
  // The JWT does NOT contain the identities array, so we must fetch fresh user data.
  await verifySession(); // Still verify user is authenticated
  const supabase = await createSupabaseServerClient();

  // Fetch fresh user data to get the identities array
  const { data: { user: freshUser }, error: userError } = await supabase.auth.getUser();

  if (userError || !freshUser) {
    throw new Error('Failed to get user data');
  }

  // Find Google identity
  const googleIdentity = freshUser.identities?.find(
    (identity: { provider: string }) => identity.provider === 'google'
  );

  if (!googleIdentity) {
    logger.error('No Google identity found:', {
      userId: freshUser.id,
      identities: freshUser.identities?.map(i => i.provider) ?? [],
    });
    throw new Error('Ingen Google-konto funnet');
  }

  logger.info('Unlinking Google identity:', {
    identityId: googleIdentity.identity_id,
    provider: googleIdentity.provider,
    userId: freshUser.id,
  });

  // Unlink the identity - pass the whole identity object
  const { error } = await supabase.auth.unlinkIdentity(googleIdentity);

  if (error) {
    logger.error('Failed to unlink Google identity:', error);
    throw error;
  }

  invalidateAndRevalidate(freshUser.id);
  return { success: true };
}

export async function connectAppleAccount(redirectUrl: string) {
  await verifySession();
  const supabase = await createSupabaseServerClient();

  // linkIdentity returns a URL that the client needs to navigate to
  const { data, error } = await supabase.auth.linkIdentity({
    provider: 'apple',
    options: {
      redirectTo: redirectUrl,
    },
  });

  if (error) {
    logger.error('Failed to link Apple identity:', error);
    throw error;
  }

  // Return the OAuth URL for the client to navigate to
  return { url: data.url };
}

export async function disconnectAppleAccount() {
  // verifySession() uses getClaims() which parses the JWT locally.
  // The JWT does NOT contain the identities array, so we must fetch fresh user data.
  await verifySession(); // Still verify user is authenticated
  const supabase = await createSupabaseServerClient();

  // Fetch fresh user data to get the identities array
  const { data: { user: freshUser }, error: userError } = await supabase.auth.getUser();

  if (userError || !freshUser) {
    throw new Error('Failed to get user data');
  }

  // Find Apple identity
  const appleIdentity = freshUser.identities?.find(
    (identity: { provider: string }) => identity.provider === 'apple'
  );

  if (!appleIdentity) {
    logger.error('No Apple identity found:', {
      userId: freshUser.id,
      identities: freshUser.identities?.map(i => i.provider) ?? [],
    });
    throw new Error('Ingen Apple-konto funnet');
  }

  logger.info('Unlinking Apple identity:', {
    identityId: appleIdentity.identity_id,
    provider: appleIdentity.provider,
    userId: freshUser.id,
  });

  // Unlink the identity - pass the whole identity object
  const { error } = await supabase.auth.unlinkIdentity(appleIdentity);

  if (error) {
    logger.error('Failed to unlink Apple identity:', error);
    throw error;
  }

  invalidateAndRevalidate(freshUser.id);
  return { success: true };
}

export async function linkPhoneNumber(phone: string) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Store the pending phone number in user metadata AND initiate phone change in a single call.
  // IMPORTANT: Using a single updateUser call ensures both the metadata and phone change
  // are applied atomically. Two separate calls can cause the second call to not preserve
  // the metadata from the first call (race condition or Supabase behavior).
  const existingMetadata = user.user_metadata ?? {};

  const { error } = await supabase.auth.updateUser({
    phone,
    data: {
      ...existingMetadata,
      pendingPhone: phone,
    },
  });

  if (error) {
    logger.error('Failed to initiate phone linking:', error);
    throw error;
  }

  logger.info('OTP sent for phone linking:', { phone, userId: user.id });
  return { success: true };
}

export async function verifyAndLinkPhone(phone: string, otp: string) {
  // verifySession() uses getClaims() which parses the JWT locally.
  // After linkPhoneNumber() updates user_metadata, the JWT cookie may not be refreshed yet.
  // So we must fetch fresh user data from Supabase to get the updated pendingPhone.
  await verifySession(); // Still verify user is authenticated
  const supabase = await createSupabaseServerClient();

  // Fetch fresh user data to get the updated pendingPhone metadata
  const { data: { user: freshUser }, error: userError } = await supabase.auth.getUser();

  if (userError || !freshUser) {
    throw new Error('Failed to get user data');
  }

  // Verify that this phone matches the pending phone
  const pendingPhone = freshUser.user_metadata?.pendingPhone;
  if (pendingPhone !== phone) {
    logger.error('Phone number mismatch:', {
      expected: phone,
      actual: pendingPhone,
      userId: freshUser.id,
      hasMetadata: !!freshUser.user_metadata,
      metadataKeys: freshUser.user_metadata ? Object.keys(freshUser.user_metadata) : [],
    });
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
  // verifySession() uses getClaims() which parses the JWT locally.
  // The JWT does NOT contain the identities array, so we must fetch fresh user data.
  await verifySession(); // Still verify user is authenticated
  const supabase = await createSupabaseServerClient();

  // Fetch fresh user data to get the identities array
  const { data: { user: freshUser }, error: userError } = await supabase.auth.getUser();

  if (userError || !freshUser) {
    throw new Error('Failed to get user data');
  }

  // Find phone identity
  const phoneIdentity = freshUser.identities?.find(
    (identity: { provider: string }) => identity.provider === 'phone'
  );

  if (!phoneIdentity) {
    logger.error('No phone identity found:', {
      userId: freshUser.id,
      identities: freshUser.identities?.map(i => i.provider) ?? [],
    });
    throw new Error('Ingen telefonnummer funnet');
  }

  logger.info('Unlinking phone identity:', {
    identityId: phoneIdentity.identity_id,
    provider: phoneIdentity.provider,
    userId: freshUser.id,
  });

  // Unlink the identity
  const { error } = await supabase.auth.unlinkIdentity(phoneIdentity);

  if (error) {
    logger.error('Failed to unlink phone identity:', error);
    throw error;
  }

  invalidateAndRevalidate(freshUser.id);
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
  // Block password changes while impersonating
  await enforceNotImpersonating('change_password');

  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Validate password length
  if (password.length < 6) {
    throw new Error('Passordet må være minst 6 tegn langt');
  }

  // Update user password (with nonce if provided for phone-only users)
  // Store a metadata flag since Supabase doesn't always add an "email" identity on OAuth users.
  const updateData: { password: string; nonce?: string; data?: Record<string, unknown> } = {
    password,
    data: { hasPassword: true },
  };
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
  // Block email changes while impersonating
  await enforceNotImpersonating('change_email');

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

/**
 * Permanently delete the user's account and all associated data.
 *
 * This action:
 * 1. Blocks if user is currently being impersonated (security)
 * 2. Calls prepare_user_for_deletion() to clean up internal tables
 * 3. Deletes the auth user via admin API (cascades to public tables)
 * 4. Signs out the user
 *
 * The user will be redirected to the login page by the client after this action.
 */
export async function deleteUserAccount(): Promise<{ success: boolean }> {
  // Block account deletion while impersonating
  await enforceNotImpersonating('delete_account');

  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  logger.info('Starting account deletion:', { userId: user.id });

  try {
    // Step 1: Call the database function to clean up internal tables
    // This also logs the deletion in admin_audit_log before the user is deleted
    const { error: cleanupError } = await supabase.rpc('prepare_user_for_deletion', {
      target_user_id: user.id,
    });

    if (cleanupError) {
      logger.error('Failed to prepare user for deletion:', cleanupError);
      throw new Error('Failed to delete account. Please try again.');
    }

    // Step 2: Delete the auth user using service role (admin API)
    // This will cascade delete all public schema data via FK constraints
    const serviceClient = createSupabaseServiceClient();
    const { error: deleteError } = await serviceClient.auth.admin.deleteUser(user.id);

    if (deleteError) {
      logger.error('Failed to delete auth user:', deleteError);
      throw new Error('Failed to delete account. Please try again.');
    }

    logger.info('Account deleted successfully:', { userId: user.id });

    // Step 3: Sign out the user (clear session cookies)
    await supabase.auth.signOut();

    return { success: true };
  } catch (error) {
    logger.error('Account deletion failed:', error);
    throw error;
  }
}
