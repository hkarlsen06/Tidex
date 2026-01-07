"use client";

import { useEffect, useCallback, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import PullToRefresh from "react-simple-pull-to-refresh";
import { useScrollRestoration } from "@/lib/hooks/useScrollRestoration";
import { useScrollContext } from "@/lib/contexts/ScrollContext";

interface CenteredPageWrapperProps {
  children: ReactNode;
  /**
   * Unique key for scroll restoration (e.g., "home", "settings").
   * If not provided, scroll restoration is disabled.
   */
  routeKey?: string;
  /**
   * Enable pull-to-refresh functionality.
   * When enabled, pulling down at the top of the scroll container will trigger a page refresh.
   */
  pullToRefresh?: boolean;
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
  pullToRefresh = false,
}: CenteredPageWrapperProps) {
  const scrollRef = useScrollRestoration(routeKey ?? "");
  const { registerScrollContainer } = useScrollContext();
  const router = useRouter();

  const handleRefresh = useCallback(async () => {
    router.refresh();
    // Small delay to ensure the refresh is visible to the user
    await new Promise((resolve) => setTimeout(resolve, 500));
  }, [router]);

  useEffect(() => {
    if (routeKey) {
      registerScrollContainer(scrollRef.current);
      return () => registerScrollContainer(null);
    }
  }, [routeKey, registerScrollContainer, scrollRef]);

  const content = (
    <div className="w-full max-w-md md:max-w-lg mx-auto my-auto min-h-full flex flex-col justify-center pt-2 pb-6">
      {children}
    </div>
  );

  return (
    <div
      ref={routeKey ? scrollRef : undefined}
      className="h-full px-4 pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8 overflow-y-auto"
    >
      {pullToRefresh ? (
        <PullToRefresh
          onRefresh={handleRefresh}
          pullingContent=""
          resistance={2.5}
        >
          {content}
        </PullToRefresh>
      ) : (
        content
      )}
    </div>
  );
}
