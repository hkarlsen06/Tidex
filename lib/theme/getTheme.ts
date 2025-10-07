import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type Theme = "light" | "dark";

/**
 * Get user's theme preference from database
 * Returns null if user is not authenticated or theme is not set
 */
export async function getUserTheme(): Promise<Theme | null> {
  const supabase = await createSupabaseServerClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return null;
  }

  const { data: settings } = await supabase
    .from("user_settings")
    .select("theme")
    .eq("user_id", user.id)
    .single();

  if (settings?.theme === "light" || settings?.theme === "dark") {
    return settings.theme;
  }

  return null;
}
