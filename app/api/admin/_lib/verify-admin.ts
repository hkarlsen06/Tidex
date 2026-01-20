import { NextRequest } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { createSupabaseServerClient } from '@/lib/supabase/server';

/**
 * Superadmin user ID - only this user can grant/revoke admin privileges
 * This is Hjalmar's account (primary developer)
 */
export const SUPERADMIN_USER_ID = '032d8c2a-9af6-4777-99f0-24e2c4058bf3';

export interface AdminUser {
  id: string;
  email?: string;
}

export interface AdminVerificationResult {
  user: AdminUser;
  isSuperAdmin: boolean;
}

/**
 * Verify that the request is from an authenticated admin user.
 * Supports both Bearer token (iOS native) and cookie-based (web) authentication.
 *
 * @param request - The Next.js request object
 * @returns The admin user if verified, null if not authenticated or not an admin
 */
export async function verifyAdminFromRequest(
  request: NextRequest
): Promise<AdminVerificationResult | null> {
  let userId: string | null = null;
  let userEmail: string | undefined;
  let isAdmin = false;

  // 1. Try Bearer token first (native iOS app)
  const authHeader = request.headers.get('Authorization');
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.substring(7);

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

    const { data, error } = await supabaseWithToken.auth.getUser();
    if (!error && data.user) {
      userId = data.user.id;
      userEmail = data.user.email;
      isAdmin = data.user.app_metadata?.role === 'admin';
    }
  }

  // 2. Fall back to cookie-based session (web app)
  if (!userId) {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.getUser();
    if (!error && data.user) {
      userId = data.user.id;
      userEmail = data.user.email;
      isAdmin = data.user.app_metadata?.role === 'admin';
    }
  }

  // Not authenticated
  if (!userId) {
    return null;
  }

  // Not an admin
  if (!isAdmin) {
    return null;
  }

  return {
    user: {
      id: userId,
      email: userEmail,
    },
    isSuperAdmin: userId === SUPERADMIN_USER_ID,
  };
}

/**
 * Validate UUID format
 */
export function isValidUUID(id: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    id
  );
}
