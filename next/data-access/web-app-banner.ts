import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export const WEB_APP_SUNSET_BANNER_KEY = "web-app-sunset-2026-04-01";

type RecordWebAppBannerDismissalInput = {
  bannerKey: string;
  userId: string;
};

export async function recordWebAppBannerDismissal({
  bannerKey,
  userId,
}: RecordWebAppBannerDismissalInput) {
  const supabase = await createSupabaseServerClient();
  const dismissedAt = new Date().toISOString();

  const { error } = await supabase
    .from("web_app_banner_dismissals")
    .upsert(
      {
        banner_key: bannerKey,
        user_id: userId,
        dismissed_at: dismissedAt,
      },
      {
        onConflict: "banner_key,user_id",
      }
    );

  if (error) {
    throw error;
  }
}
