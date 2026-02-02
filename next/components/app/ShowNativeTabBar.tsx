"use client";

import { useLayoutEffect } from "react";
import { NativeTabBar } from "@/lib/capacitor/native-tab-bar";
import { hideSplash } from "@/lib/capacitor/native-splash";
import { isNativeIOSWithFallback } from "@/lib/capacitor/platform";

/**
 * Component that shows the native iOS tab bar when mounted.
 * The tab bar is automatically hidden again when this component unmounts.
 *
 * Use this in the main app layout to show the tab bar for authenticated routes.
 * The native tab bar starts hidden by default to prevent it from flashing
 * on login/onboarding screens.
 *
 * Uses useLayoutEffect to show tab bar synchronously before browser paint,
 * ensuring the tab bar appears at the same time as the dashboard content.
 *
 * Shows tab bar and hides splash screen simultaneously for a seamless transition.
 */
export function ShowNativeTabBar() {
  useLayoutEffect(() => {
    // Only run on native iOS (uses fallback for when Capacitor bridge isn't ready)
    if (!isNativeIOSWithFallback()) {
      return;
    }

    // Show tab bar and hide splash simultaneously for seamless transition
    NativeTabBar.show().catch((error) => {
      console.error("[ShowNativeTabBar] Failed to show:", error);
    });
    hideSplash(200);

    // Hide the tab bar when component unmounts (e.g., logout)
    return () => {
      NativeTabBar.hide().catch((error) => {
        console.error("[ShowNativeTabBar] Failed to hide:", error);
      });
    };
  }, []);

  return null;
}
