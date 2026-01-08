"use client";

import { useEffect } from "react";
import { isNativePlatform } from "@/lib/capacitor/platform";
import { hideSplash, isSplashHidden } from "@/lib/capacitor/native-splash";

/**
 * SplashScreenManager - Safety net fallback for native splash screen.
 *
 * The splash screen is primarily hidden by:
 * - ShowNativeTabBar: For authenticated routes (after tab bar is shown)
 * - LoginClient/SignupPage: For auth routes (when form is ready)
 *
 * This component is a FALLBACK safety net that ensures users are never stuck
 * on the splash screen if something fails. After 3 seconds, if the splash
 * hasn't been hidden by a primary handler, this component hides it.
 *
 * The hideSplash() function is idempotent, so multiple calls are safe.
 */
export function SplashScreenManager() {
  useEffect(() => {
    // Only run on native platforms
    if (!isNativePlatform()) return;

    // Wait for primary handlers to hide splash (ShowNativeTabBar, LoginClient, etc.)
    // If splash isn't hidden after 3 seconds, hide it as a safety fallback
    const fallbackTimeout = setTimeout(() => {
      if (!isSplashHidden()) {
        console.warn("[SplashScreenManager] Fallback triggered - primary handler did not hide splash");
        hideSplash(200);
      }
    }, 3000);

    return () => {
      clearTimeout(fallbackTimeout);
    };
  }, []);

  return null;
}
