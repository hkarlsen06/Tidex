"use server";

import { verifySession } from "@/data-access/auth";
import {
  WEB_APP_SUNSET_BANNER_KEY,
  recordWebAppBannerDismissal,
} from "@/data-access/web-app-banner";
import { logger } from "@/lib/logger";

export async function logWebAppSunsetBannerDismissal(): Promise<{ success: boolean }> {
  try {
    const { user } = await verifySession();

    await recordWebAppBannerDismissal({
      bannerKey: WEB_APP_SUNSET_BANNER_KEY,
      userId: user.id,
    });

    return { success: true };
  } catch (error) {
    logger.error("Failed to log web app sunset banner dismissal:", error);
    return { success: false };
  }
}
