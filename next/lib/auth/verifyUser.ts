import "server-only";
import type { User } from "@supabase/supabase-js";
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
 * Uses getClaims() for performance - parses JWT locally without network request.
 * See: https://supabase.com/docs/reference/javascript/auth-getclaims
 *
 * Implements refresh-then-signout policy:
 * - On invalid JWT: attempts ONE session refresh
 * - If still invalid: signs out and redirects to /login
 *
 * @throws Redirects to /login on auth failure
 * @returns Verified user object (minimal User with data from JWT claims)
 */
export async function verifyUser(): Promise<User> {
  const supabase = await createSupabaseServerClient();

  // Use getClaims() for performance - parses JWT locally without network request
  const { data, error } = await supabase.auth.getClaims();

  if (error || !data?.claims) {
    // Attempt recovery with refresh-then-signout policy
    await handleAuthError(error || new Error("No valid session"));
    // Will not reach here - handleAuthError redirects
    throw new Error("Unreachable");
  }

  const claims = data.claims;

  // Create a minimal User object from JWT claims for backward compatibility
  const user: User = {
    id: claims.sub,
    email: claims.email,
    phone: claims.phone,
    user_metadata: claims.user_metadata ?? {},
    app_metadata: claims.app_metadata ?? {},
    aud: claims.aud ?? "authenticated",
    created_at: "",
  } as User;

  return user;
}
