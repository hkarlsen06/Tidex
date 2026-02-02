"use client";

import { useEffect, type ReactNode } from "react";
import { useScrollRestoration } from "@/lib/hooks/useScrollRestoration";
import { useScrollContext } from "@/lib/contexts/ScrollContext";
import { useHasNativeTabBar } from "@/lib/contexts/NativeTabBarContext";

interface CenteredPageWrapperProps {
  children: ReactNode;
  /**
   * Unique key for scroll restoration (e.g., "home", "settings").
   * If not provided, scroll restoration is disabled.
   */
  routeKey?: string;
}

/**
 * Wrapper for pages that should center their content in the available viewport.
 * Content only scrolls when it exceeds the available space between header and navbar.
 *
 * Use this for:
 * - Dashboard (home page)
 * - Short content pages that should be centered
 */
export function CenteredPageWrapper({
  children,
  routeKey,
}: CenteredPageWrapperProps) {
  const scrollRef = useScrollRestoration(routeKey ?? "");
  const { registerScrollContainer } = useScrollContext();
  const hasNativeTabBar = useHasNativeTabBar();

  useEffect(() => {
    if (routeKey) {
      registerScrollContainer(scrollRef.current);
      return () => registerScrollContainer(null);
    }
  }, [routeKey, registerScrollContainer, scrollRef]);

  // Native iOS: safe area handles tab bar automatically
  // Web: full padding for web NavBar (5rem + safe area)
  const bottomPadding = hasNativeTabBar
    ? "pb-[env(safe-area-inset-bottom)]"
    : "pb-[calc(5rem+env(safe-area-inset-bottom))]";

  return (
    <div
      ref={routeKey ? scrollRef : undefined}
      data-page-wrapper
      className={`h-full px-4 ${bottomPadding} md:pb-8 overflow-y-auto`}
    >
      <div className="w-full max-w-md md:max-w-lg mx-auto my-auto min-h-full flex flex-col justify-center pt-2 pb-6">
        {children}
      </div>
    </div>
  );
}
