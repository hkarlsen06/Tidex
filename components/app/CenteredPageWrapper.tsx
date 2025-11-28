"use client";

import { useEffect, type ReactNode } from "react";
import { useScrollRestoration } from "@/lib/hooks/useScrollRestoration";
import { useScrollContext } from "@/lib/contexts/ScrollContext";

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

  useEffect(() => {
    if (routeKey) {
      registerScrollContainer(scrollRef.current);
      return () => registerScrollContainer(null);
    }
  }, [routeKey, registerScrollContainer, scrollRef]);

  return (
    <div
      ref={routeKey ? scrollRef : undefined}
      className="h-full px-4 pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8 overflow-y-auto"
    >
      <div className="w-full max-w-md md:max-w-lg mx-auto my-auto min-h-full flex flex-col justify-center pt-2 pb-6">
        {children}
      </div>
    </div>
  );
}
