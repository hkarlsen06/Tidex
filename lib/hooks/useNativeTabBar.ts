"use client";

import { useEffect, useCallback, useRef } from "react";
import { usePathname, useRouter } from "next/navigation";
import { isIOSPlatform } from "@/lib/capacitor/platform";
import { useLocale } from "@/lib/i18n/client";
import { useScrollContext } from "@/lib/contexts/ScrollContext";
import type { PluginListenerHandle } from "@capacitor/core";
// Import at module scope - no dynamic imports on route changes
import { NativeTabBar, getTabIndexFromPath } from "@/lib/capacitor/native-tab-bar";

/**
 * Hook to synchronize native iOS tab bar with web navigation.
 *
 * Responsibilities:
 * - Native tab taps trigger router.push() (SPA navigation, no reload)
 * - Re-tapping the current tab scrolls to top
 * - Web route changes update native tab selection
 * - Non-tab routes clear selection (no tab highlighted)
 *
 * Note: Tab titles are NOT set from this hook. The native tab bar derives its
 * locale from iOS Settings (via Locale.preferredLanguages in Swift), which
 * ensures the tab bar language matches the web content without additional sync.
 */
export function useNativeTabBar() {
  const pathname = usePathname();
  const router = useRouter();
  const locale = useLocale();
  const { scrollToTop } = useScrollContext();
  const listenerRef = useRef<PluginListenerHandle | null>(null);
  const reselectedListenerRef = useRef<PluginListenerHandle | null>(null);
  const isAvailableRef = useRef<boolean | null>(null); // Cache availability
  const lastSelectedIndexRef = useRef<number>(0);
  const availabilityTimeoutRef = useRef<number | null>(null);
  const availabilityAttemptsRef = useRef(0);
  // Ref to track if listeners are set up (stable across re-renders)
  const listenersSetupRef = useRef(false);
  // Refs for callbacks to avoid effect re-runs
  const handleTabSelectedRef = useRef<(event: { index: number; route: string }) => void>(undefined);
  const scrollToTopRef = useRef<(() => void) | undefined>(undefined);

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
    if (!isIOSPlatform() && !document.documentElement.classList.contains("native-ios")) {
      return;
    }
    if (listenersSetupRef.current) return; // Already initialized

    let mounted = true;
    const maxAvailabilityAttempts = 20;
    const availabilityRetryDelayMs = 100;

    const scheduleRetry = () => {
      if (!mounted) return;
      if (availabilityAttemptsRef.current >= maxAvailabilityAttempts) return;
      availabilityAttemptsRef.current += 1;
      availabilityTimeoutRef.current = window.setTimeout(
        initialize,
        availabilityRetryDelayMs
      );
    };

    const initialize = async () => {
      if (!isIOSPlatform()) {
        scheduleRetry();
        return;
      }

      try {
        const { available } = await NativeTabBar.isAvailable();
        if (!mounted) return;

        isAvailableRef.current = available;
        if (!available) {
          scheduleRetry();
          return;
        }

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
        availabilityAttemptsRef.current = 0;

      } catch (error) {
        console.error("[NativeTabBar] Init failed:", error);
        scheduleRetry();
      }
    };

    initialize();

    return () => {
      mounted = false;
      if (availabilityTimeoutRef.current) {
        window.clearTimeout(availabilityTimeoutRef.current);
        availabilityTimeoutRef.current = null;
      }
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
