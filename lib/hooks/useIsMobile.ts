"use client";

import { useSyncExternalStore } from "react";

const MOBILE_BREAKPOINT = 640; // sm breakpoint in Tailwind
const DESKTOP_BREAKPOINT = 1024; // lg breakpoint in Tailwind

/**
 * Subscribes to window resize events.
 * Returns an unsubscribe function for useSyncExternalStore.
 */
function subscribeToResize(callback: () => void) {
  window.addEventListener("resize", callback);
  return () => window.removeEventListener("resize", callback);
}

/**
 * Hook to detect if the current viewport is mobile-sized.
 * Uses 640px (sm breakpoint) as the threshold.
 *
 * Returns `undefined` during SSR/hydration to allow components to render
 * a neutral state and avoid layout shift when the actual viewport is detected.
 */
export function useIsMobile(): boolean | undefined {
  const isMobile = useSyncExternalStore(
    subscribeToResize,
    () => window.innerWidth < MOBILE_BREAKPOINT,
    () => undefined // Server snapshot - undefined means "not yet known"
  );

  return isMobile;
}

/**
 * Hook to detect if the current viewport is desktop-sized.
 * Uses 1024px (lg breakpoint) as the threshold.
 *
 * Returns `undefined` during SSR/hydration to allow components to render
 * a neutral state and avoid layout shift when the actual viewport is detected.
 */
export function useIsDesktop(): boolean | undefined {
  const isDesktop = useSyncExternalStore(
    subscribeToResize,
    () => window.innerWidth >= DESKTOP_BREAKPOINT,
    () => undefined // Server snapshot - undefined means "not yet known"
  );

  return isDesktop;
}
