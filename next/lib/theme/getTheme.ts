import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type Theme = "light" | "dark" | "system";

/**
 * Get user's theme preference from database
 * Returns null if user is not authenticated or theme is not set
 *
 * Uses getClaims() for performance - parses JWT locally without network request.
 * See: https://supabase.com/docs/reference/javascript/auth-getclaims
 */
export async function getUserTheme(): Promise<Theme | null> {
  const supabase = await createSupabaseServerClient();

  // Use getClaims() for performance - parses JWT locally without network request
  const { data, error } = await supabase.auth.getClaims();

  if (error || !data?.claims) {
    return null;
  }

  const { data: settings } = await supabase
    .from("user_settings")
    .select("theme")
    .eq("user_id", data.claims.sub)
    .single();

  if (settings?.theme === "light" || settings?.theme === "dark" || settings?.theme === "system") {
    return settings.theme;
  }

  return null;
}
