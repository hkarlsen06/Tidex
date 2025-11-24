"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";

export async function updateTheme(theme: "light" | "dark"): Promise<{ success: boolean }> {
  const supabase = await createSupabaseServerClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { success: false };
  }

  const { error } = await supabase
    .from("user_settings")
    .update({ theme })
    .eq("user_id", user.id);

  if (error) {
    console.error("Failed to update theme:", error);
    return { success: false };
  }

  // Invalidate cache to ensure server-rendered components use new theme
  invalidateAndRevalidate(user.id);

  return { success: true };
}
