"use client";

import { useEffect, useCallback, useRef } from "react";
import { usePathname, useRouter } from "next/navigation";
import { isIOSPlatform } from "@/lib/capacitor/platform";
import { useTranslations } from "@/lib/i18n/client";
import type { PluginListenerHandle } from "@capacitor/core";
// Import at module scope - no dynamic imports on route changes
import { NativeTabBar, getTabIndexFromPath } from "@/lib/capacitor/native-tab-bar";

/**
 * Hook to synchronize native iOS tab bar with web navigation.
 *
 * - Native tab taps trigger router.push() (SPA navigation, no reload)
 * - Web route changes update native tab selection
 * - Non-tab routes keep last selection (don't clear)
 */
export function useNativeTabBar() {
  const pathname = usePathname();
  const router = useRouter();
  const { locale } = useTranslations();
  const listenerRef = useRef<PluginListenerHandle | null>(null);
  const isAvailableRef = useRef<boolean | null>(null); // Cache availability
  const lastSelectedIndexRef = useRef<number>(0);
  const pathnameRef = useRef(pathname); // Capture current pathname for initial setup

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

  // Initialize plugin listener (runs once)
  useEffect(() => {
    if (!isIOSPlatform()) return;

    let mounted = true;

    const initialize = async () => {
      try {
        const { available } = await NativeTabBar.isAvailable();
        if (!mounted) return;

        isAvailableRef.current = available;
        if (!available) return;

        // Listen for tab selections from native
        listenerRef.current = await NativeTabBar.addListener(
          "tabSelected",
          handleTabSelected
        );

        // Set initial tab based on current route
        // Default to Home (0) if on non-tab route at cold start
        const initialIndex = getTabIndexFromPath(pathnameRef.current) ?? 0;
        await NativeTabBar.setSelectedTab({ index: initialIndex });
        lastSelectedIndexRef.current = initialIndex;

      } catch (error) {
        console.error("[NativeTabBar] Init failed:", error);
      }
    };

    initialize();

    return () => {
      mounted = false;
      listenerRef.current?.remove();
      listenerRef.current = null;
    };
  }, [handleTabSelected]); // Only depends on handleTabSelected, not pathname

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
