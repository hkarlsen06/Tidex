"use client";

import { useEffect, type ReactNode, type RefObject } from "react";
import { useScrollRestoration } from "@/lib/hooks/useScrollRestoration";
import { useScrollContext } from "@/lib/contexts/ScrollContext";
import { useHasNativeTabBar } from "@/lib/contexts/NativeTabBarContext";

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
}: ScrollablePageWrapperProps) {
  const scrollRef = useScrollRestoration(routeKey ?? "");
  const { registerScrollContainer } = useScrollContext();
  const hasNativeTabBar = useHasNativeTabBar();

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

  // Native iOS: safe area handles tab bar automatically
  // Web: full padding for web NavBar (5rem + safe area)
  const bottomPadding = hasNativeTabBar
    ? "pb-[env(safe-area-inset-bottom)]"
    : "pb-[calc(5rem+env(safe-area-inset-bottom))]";

  return (
    <div
      ref={routeKey ? scrollRef : undefined}
      data-page-wrapper
      className={`h-full overflow-y-auto ${bottomPadding} md:pb-8 ${className ?? ""}`}
    >
      {content}
    </div>
  );
}
