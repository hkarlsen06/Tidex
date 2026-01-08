"use client";

import { useEffect } from "react";
import { NativeTabBar } from "@/lib/capacitor/native-tab-bar";
import { isNativeIOSWithFallback } from "@/lib/capacitor/platform";

/**
 * Component that hides the native iOS tab bar when mounted.
 * The tab bar is automatically shown again when this component unmounts.
 *
 * Use this in layouts/pages where the tab bar should not be visible:
 * - Auth pages (login, signup, etc.)
 * - Onboarding flow
 * - Full-screen modals
 */
export function HideNativeTabBar() {
  useEffect(() => {
    // Only run on native iOS (uses fallback for when Capacitor bridge isn't ready)
    if (!isNativeIOSWithFallback()) {
      return;
    }

    // Hide the tab bar
    NativeTabBar.hide().catch((error) => {
      console.error("[HideNativeTabBar] Failed to hide:", error);
    });

    // Show the tab bar when component unmounts
    return () => {
      NativeTabBar.show().catch((error) => {
        console.error("[HideNativeTabBar] Failed to show:", error);
      });
    };
  }, []);

  return null;
}
