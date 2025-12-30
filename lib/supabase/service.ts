// lib/supabase/service.ts
import "server-only";
import { createClient } from "@supabase/supabase-js";

/**
 * Creates a Supabase client with service role privileges.
 * USE WITH CAUTION - bypasses RLS.
 * Only use in server actions that have already verified admin status via verifyAdmin().
 *
 * This client is used for:
 * - Admin operations that need to query across all users
 * - Calling service-role-only RPC functions
 * - Operations that bypass Row Level Security
 */
export function createSupabaseServiceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variable"
    );
  }

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });
}
