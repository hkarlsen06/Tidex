"use client";

import { useEffect, useCallback, useRef } from "react";
import { usePathname, useRouter } from "next/navigation";
import { isIOSPlatform } from "@/lib/capacitor/platform";
import { useTranslations } from "@/lib/i18n/client";
import { useScrollContext } from "@/lib/contexts/ScrollContext";
import type { PluginListenerHandle } from "@capacitor/core";
// Import at module scope - no dynamic imports on route changes
import { NativeTabBar, getTabIndexFromPath } from "@/lib/capacitor/native-tab-bar";

/**
 * Hook to synchronize native iOS tab bar with web navigation.
 *
 * - Native tab taps trigger router.push() (SPA navigation, no reload)
 * - Re-tapping the current tab scrolls to top
 * - Web route changes update native tab selection
 * - Non-tab routes clear selection (no tab highlighted)
 */
export function useNativeTabBar() {
  const pathname = usePathname();
  const router = useRouter();
  const { locale } = useTranslations();
  const { scrollToTop } = useScrollContext();
  const listenerRef = useRef<PluginListenerHandle | null>(null);
  const reselectedListenerRef = useRef<PluginListenerHandle | null>(null);
  const isAvailableRef = useRef<boolean | null>(null); // Cache availability
  const lastSelectedIndexRef = useRef<number>(0);
  // Ref to track if listeners are set up (stable across re-renders)
  const listenersSetupRef = useRef(false);
  // Refs for callbacks to avoid effect re-runs
  const handleTabSelectedRef = useRef<(event: { index: number; route: string }) => void>();
  const scrollToTopRef = useRef<() => void>();

  // Handle native tab selection - use SPA router, not WebView reload
  const handleTabSelected = useCallback(
    (event: { index: number; route: string }) => {
      const { route } = event;

      // Build full path with locale
      const fullPath = `/${locale}${route}`;

      // Use Next.js router for SPA navigation (preserves state)
      router.push(fullPath);
    },
    [locale, router]
  );

  // Keep refs updated with latest callbacks - must be in useEffect for React 19
  useEffect(() => {
    scrollToTopRef.current = scrollToTop;
    handleTabSelectedRef.current = handleTabSelected;
  });

  // Initialize plugin listeners (runs once)
  useEffect(() => {
    if (!isIOSPlatform()) return;
    if (listenersSetupRef.current) return; // Already initialized

    let mounted = true;

    const initialize = async () => {
      try {
        const { available } = await NativeTabBar.isAvailable();
        if (!mounted) return;

        isAvailableRef.current = available;
        if (!available) return;

        // Listen for tab selections from native
        // Use ref wrapper so we always call the latest callback
        listenerRef.current = await NativeTabBar.addListener(
          "tabSelected",
          (event) => handleTabSelectedRef.current?.(event)
        );

        // Listen for tab re-selections (same tab tapped again) - scroll to top
        reselectedListenerRef.current = await NativeTabBar.addListener(
          "tabReselected",
          () => scrollToTopRef.current?.()
        );

        listenersSetupRef.current = true;

      } catch (error) {
        console.error("[NativeTabBar] Init failed:", error);
      }
    };

    initialize();

    return () => {
      mounted = false;
      listenerRef.current?.remove();
      listenerRef.current = null;
      reselectedListenerRef.current?.remove();
      reselectedListenerRef.current = null;
      listenersSetupRef.current = false;
    };
  }, []); // Empty deps - only run once

  // Sync tab selection when web route changes
  useEffect(() => {
    // Skip if not on iOS or not yet initialized
    if (!isIOSPlatform() || isAvailableRef.current !== true) return;

    const syncSelection = async () => {
      try {
        const tabIndex = getTabIndexFromPath(pathname);

        if (tabIndex !== null) {
          // Route matches a tab - update selection
          await NativeTabBar.setSelectedTab({ index: tabIndex });
          lastSelectedIndexRef.current = tabIndex;
        } else {
          // Non-tab route (e.g., /settings) - clear selection
          // This shows no tab as highlighted, which is the correct UX
          await NativeTabBar.clearSelection();
          lastSelectedIndexRef.current = -1;
        }

      } catch (error) {
        console.error("[NativeTabBar] Sync failed:", error);
      }
    };

    syncSelection();
  }, [pathname]);
}
