import { NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
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
 * - Bearer token in Authorization header (native iOS app) - handled by createSupabaseServerClient
 * - Cookie-based session (web app) - handled by createSupabaseServerClient
 *
 * Response:
 * - 200: { success: true }
 * - 401: { error: string } - Not authenticated
 * - 500: { error: string } - Failed to prepare or delete account
 */
export async function DELETE() {
  try {
    // createSupabaseServerClient handles both Bearer tokens (iOS) and cookies (web)
    const supabase = await createSupabaseServerClient();
    const { data, error: authError } = await supabase.auth.getUser();

    if (authError || !data.user) {
      return NextResponse.json(
        { error: 'Not authenticated' },
        { status: 401 }
      );
    }

    const userId = data.user.id;

    logger.info('[delete-account] Starting account deletion:', { userId });

    // Step 1: Call the database function to clean up internal tables
    // This also logs the deletion in admin_audit_log before the user is deleted
    const { error: cleanupError } = await supabase.rpc('prepare_user_for_deletion', {
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
