"use client";

import { createContext, useContext, type ReactNode } from "react";
import { usePathname } from "next/navigation";

interface RouteVisibilityContextType {
  pathname: string | null;
  isRouteActive: (routePattern: string) => boolean;
}

const RouteVisibilityContext = createContext<RouteVisibilityContextType | undefined>(undefined);

/**
 * Provides route visibility tracking for AnimateActivity.
 *
 * With cacheComponents enabled, routes are hidden (display: none) rather than unmounted.
 * This context allows components to know if their route is currently active,
 * enabling proper AnimateActivity mode="visible"|"hidden" control.
 *
 * Place this provider in the root client layout so pathname updates propagate
 * to all cached route components.
 */
export function RouteVisibilityProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname();

  const isRouteActive = (routePattern: string): boolean => {
    if (!pathname) return false;
    // Simple pattern matching - supports /shifts, /stats, etc.
    // Strips locale prefix for matching (e.g., /en/shifts -> /shifts)
    const pathWithoutLocale = pathname.replace(/^\/[a-z]{2}(?=\/|$)/, '');
    return pathWithoutLocale.startsWith(routePattern);
  };

  return (
    <RouteVisibilityContext.Provider value={{ pathname, isRouteActive }}>
      {children}
    </RouteVisibilityContext.Provider>
  );
}

export function useRouteVisibility() {
  const context = useContext(RouteVisibilityContext);
  if (context === undefined) {
    throw new Error("useRouteVisibility must be used within a RouteVisibilityProvider");
  }
  return context;
}

/**
 * Hook to check if a specific route is currently active.
 * Useful for AnimateActivity mode prop.
 */
export function useIsRouteActive(routePattern: string): boolean {
  const { isRouteActive } = useRouteVisibility();
  return isRouteActive(routePattern);
}
