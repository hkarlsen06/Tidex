'use server';

import { verifySession } from '@/data-access/auth';
import { createSupabaseServerClient } from '@/lib/supabase/server';

/**
 * Get or create an app_account_token for the current user.
 * This token is used to link Apple IAP purchases to the Tidex user.
 *
 * The token is stable per user and persists across devices.
 */
export async function getAppAccountToken(): Promise<{ token: string } | { error: string }> {
  try {
    const { user } = await verifySession();
    const supabase = await createSupabaseServerClient();

    // Call the RPC function to get or create the token
    const { data, error } = await supabase.rpc('get_or_create_app_account_token', {
      p_user_id: user.id,
    });

    if (error) {
      console.error('[getAppAccountToken] RPC error:', error);
      return { error: 'Failed to get app account token' };
    }

    if (!data) {
      return { error: 'No token returned' };
    }

    return { token: data };
  } catch (e) {
    console.error('[getAppAccountToken] Exception:', e);
    return { error: 'Failed to get app account token' };
  }
}
