import { getSession } from '@/data-access/auth';

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
 * Uses centralized getSession() which supports both Bearer token (iOS native)
 * and cookie-based (web) authentication.
 *
 * @returns The admin user if verified, null if not authenticated or not an admin
 */
export async function verifyAdminFromRequest(): Promise<AdminVerificationResult | null> {
  // getSession handles both Bearer tokens (iOS) and cookies (web)
  const session = await getSession();

  // Not authenticated
  if (!session) {
    return null;
  }

  const user = session.user;
  const isAdmin = user.app_metadata?.role === 'admin';

  // Not an admin
  if (!isAdmin) {
    return null;
  }

  return {
    user: {
      id: user.id,
      email: user.email,
    },
    isSuperAdmin: user.id === SUPERADMIN_USER_ID,
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

/**
 * Check if an error is a Next.js internal error that should be re-thrown.
 * This includes prerender bailout errors (NEXT_PRERENDER_INTERRUPTED) and other
 * framework-level errors that have a 'digest' property starting with 'NEXT_'.
 *
 * These errors should not be caught and logged - they signal to Next.js that
 * the route needs dynamic rendering.
 */
export function isNextInternalError(error: unknown): boolean {
  return (
    error instanceof Error &&
    'digest' in error &&
    typeof (error as Error & { digest?: string }).digest === 'string' &&
    (error as Error & { digest: string }).digest.startsWith('NEXT_')
  );
}
