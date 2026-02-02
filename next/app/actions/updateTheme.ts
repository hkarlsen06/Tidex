"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";

/**
 * Update user's theme preference
 *
 * Uses getClaims() for performance - parses JWT locally without network request.
 * See: https://supabase.com/docs/reference/javascript/auth-getclaims
 */
export async function updateTheme(theme: "light" | "dark"): Promise<{ success: boolean }> {
  const supabase = await createSupabaseServerClient();

  // Use getClaims() for performance - parses JWT locally without network request
  const { data, error: authError } = await supabase.auth.getClaims();

  if (authError || !data?.claims) {
    return { success: false };
  }

  const userId = data.claims.sub;

  const { error } = await supabase
    .from("user_settings")
    .update({ theme })
    .eq("user_id", userId);

  if (error) {
    console.error("Failed to update theme:", error);
    return { success: false };
  }

  // Invalidate cache to ensure server-rendered components use new theme
  invalidateAndRevalidate(userId);

  return { success: true };
}
