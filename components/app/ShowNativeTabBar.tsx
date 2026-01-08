"use client";

import { useEffect } from "react";
import { NativeTabBar } from "@/lib/capacitor/native-tab-bar";
import { hideSplash } from "@/lib/capacitor/native-splash";
import { isIOSPlatform } from "@/lib/capacitor/platform";

/**
 * Component that shows the native iOS tab bar when mounted.
 * The tab bar is automatically hidden again when this component unmounts.
 *
 * Use this in the main app layout to show the tab bar for authenticated routes.
 * The native tab bar starts hidden by default to prevent it from flashing
 * on login/onboarding screens.
 *
 * Also hides the splash screen after the tab bar is shown, ensuring a smooth
 * transition where all UI elements are ready before the splash disappears.
 */
export function ShowNativeTabBar() {
  useEffect(() => {
    // Only run on native iOS
    if (!isIOSPlatform() && !document.documentElement.classList.contains("native-ios")) {
      return;
    }

    const showTabBarAndHideSplash = async () => {
      try {
        // Show the tab bar first
        await NativeTabBar.show();

        // Small delay to ensure tab bar is rendered, then hide splash
        setTimeout(() => {
          hideSplash(200);
        }, 50);
      } catch (error) {
        console.error("[ShowNativeTabBar] Failed to show:", error);
        // Even if tab bar fails, try to hide splash so user isn't stuck
        hideSplash(200);
      }
    };

    showTabBarAndHideSplash();

    // Hide the tab bar when component unmounts (e.g., logout)
    return () => {
      NativeTabBar.hide().catch((error) => {
        console.error("[ShowNativeTabBar] Failed to hide:", error);
      });
    };
  }, []);

  return null;
}
