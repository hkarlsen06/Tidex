import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { handleAuthError } from "./error-recovery";

/**
 * Verify user identity on the server by validating the JWT.
 *
 * This MUST be used in:
 * - Server actions that modify data
 * - API routes that gate access to protected resources
 * - Any server code that makes authorization decisions
 *
 * Do NOT use cached session?.user for authorization.
 * Always call this function to get a verified user identity.
 *
 * Implements refresh-then-signout policy:
 * - On 401: attempts ONE session refresh
 * - If still 401: signs out and redirects to /login
 *
 * @throws Redirects to /login on auth failure
 * @returns Verified user object
 */
export async function verifyUser() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    // Attempt recovery with refresh-then-signout policy
    await handleAuthError(error || new Error("No user found"));
    // Will not reach here - handleAuthError redirects
  }

  return user;
}
