"use client";

import { useEffect, useCallback, type ReactNode, type RefObject } from "react";
import { useRouter } from "next/navigation";
import PullToRefresh from "react-simple-pull-to-refresh";
import { useScrollRestoration } from "@/lib/hooks/useScrollRestoration";
import { useScrollContext } from "@/lib/contexts/ScrollContext";

interface ScrollablePageWrapperProps {
  children: ReactNode;
  /**
   * Unique key for scroll restoration (e.g., "shifts", "stats").
   * If not provided, scroll restoration is disabled.
   */
  routeKey?: string;
  /**
   * Additional CSS classes for the scroll container.
   */
  className?: string;
  /**
   * Whether to apply the default max-width and padding.
   * Set to false for pages that manage their own container (e.g., ShiftsView).
   */
  applyContainer?: boolean;
  /**
   * Optional ref callback to expose the scroll container ref to parent.
   */
  scrollRefCallback?: (ref: RefObject<HTMLDivElement | null>) => void;
  /**
   * Enable pull-to-refresh functionality.
   * When enabled, pulling down at the top of the scroll container will trigger a page refresh.
   */
  pullToRefresh?: boolean;
}

/**
 * Wrapper for pages that have scrollable content.
 * Provides scroll restoration and registers with ScrollContext for NavBar integration.
 *
 * Use this for:
 * - Shifts page
 * - Stats page
 * - Any page with content that typically exceeds viewport height
 */
export function ScrollablePageWrapper({
  children,
  routeKey,
  className,
  applyContainer = true,
  scrollRefCallback,
  pullToRefresh = false,
}: ScrollablePageWrapperProps) {
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

  useEffect(() => {
    if (scrollRefCallback) {
      scrollRefCallback(scrollRef);
    }
  }, [scrollRefCallback, scrollRef]);

  const content = applyContainer ? (
    <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
      {children}
    </div>
  ) : (
    children
  );

  return (
    <div
      ref={routeKey ? scrollRef : undefined}
      className={`h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8 ${className ?? ""}`}
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
