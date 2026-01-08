"use client";

import { useEffect } from "react";
import { Capacitor } from "@capacitor/core";
import { hideSplash, isSplashHidden } from "@/lib/capacitor/native-splash";

/**
 * SplashScreenManager - Fallback handler for native splash screen.
 *
 * The splash screen is primarily hidden by ShowNativeTabBar after the tab bar
 * is shown (for authenticated routes). This component acts as a fallback for:
 *
 * 1. Auth pages (login, signup) - ShowNativeTabBar isn't mounted
 * 2. Error recovery - ensures users aren't stuck on splash if something fails
 *
 * Uses a timeout to wait for the primary hide mechanism, then hides as fallback.
 */
export function SplashScreenManager() {
  useEffect(() => {
    // Only run on native platforms
    if (!Capacitor.isNativePlatform()) return;

    // Wait for ShowNativeTabBar to handle hiding (authenticated routes)
    // If splash isn't hidden after 3 seconds, hide it as fallback
    const fallbackTimeout = setTimeout(() => {
      if (!isSplashHidden()) {
        hideSplash(200);
      }
    }, 3000);

    return () => {
      clearTimeout(fallbackTimeout);
    };
  }, []);

  return null;
}
