import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { createClient } from '@supabase/supabase-js';
import { logger } from '@/lib/logger';

/**
 * DELETE /api/delete-account
 *
 * Permanently deletes the authenticated user's account and all associated data.
 *
 * This endpoint:
 * 1. Verifies user authentication (Bearer token or cookie session)
 * 2. Calls prepare_user_for_deletion() RPC to clean up internal schema tables
 * 3. Deletes the auth user via admin API (cascades to public tables via FK)
 *
 * Authentication:
 * - Bearer token in Authorization header (native iOS app)
 * - Cookie-based session (web app fallback)
 *
 * Response:
 * - 200: { success: true }
 * - 401: { error: string } - Not authenticated
 * - 500: { error: string } - Failed to prepare or delete account
 */
export async function DELETE(request: NextRequest) {
  try {
    // Try to authenticate via Bearer token first (native apps)
    const authHeader = request.headers.get('Authorization');
    let userId: string | null = null;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let supabaseForRpc: any = null;

    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.substring(7);

      // Create a Supabase client with the user's JWT to verify it
      const supabaseWithToken = createClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
        {
          global: {
            headers: {
              Authorization: `Bearer ${token}`,
            },
          },
        }
      );

      const { data, error: authError } = await supabaseWithToken.auth.getUser();
      if (!authError && data.user) {
        userId = data.user.id;
        supabaseForRpc = supabaseWithToken;
      }
    }

    // Fall back to cookie-based session (web app)
    if (!userId) {
      const supabase = await createSupabaseServerClient();
      const { data, error: authError } = await supabase.auth.getUser();
      if (!authError && data.user) {
        userId = data.user.id;
        supabaseForRpc = supabase;
      }
    }

    if (!userId || !supabaseForRpc) {
      return NextResponse.json(
        { error: 'Not authenticated' },
        { status: 401 }
      );
    }

    logger.info('[delete-account] Starting account deletion:', { userId });

    // Step 1: Call the database function to clean up internal tables
    // This also logs the deletion in admin_audit_log before the user is deleted
    const { error: cleanupError } = await supabaseForRpc.rpc('prepare_user_for_deletion', {
      target_user_id: userId,
    });

    if (cleanupError) {
      logger.error('[delete-account] Failed to prepare user for deletion:', cleanupError);
      return NextResponse.json(
        { error: 'Failed to delete account. Please try again.' },
        { status: 500 }
      );
    }

    // Step 2: Delete the auth user using service role (admin API)
    // This will cascade delete all public schema data via FK constraints
    const serviceClient = createSupabaseServiceClient();
    const { error: deleteError } = await serviceClient.auth.admin.deleteUser(userId);

    if (deleteError) {
      logger.error('[delete-account] Failed to delete auth user:', deleteError);
      return NextResponse.json(
        { error: 'Failed to delete account. Please try again.' },
        { status: 500 }
      );
    }

    logger.info('[delete-account] Account deleted successfully:', { userId });

    return NextResponse.json({ success: true });
  } catch (error) {
    logger.error('[delete-account] Unexpected error:', error);
    return NextResponse.json(
      { error: 'An unexpected error occurred' },
      { status: 500 }
    );
  }
}
