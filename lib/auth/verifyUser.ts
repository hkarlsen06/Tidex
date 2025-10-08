import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";

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
 * @throws Error if user is not authenticated or token is invalid
 * @returns Verified user object
 */
export async function verifyUser() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    throw new Error("Unauthorized");
  }

  return user;
}
