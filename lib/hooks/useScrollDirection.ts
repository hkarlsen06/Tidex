"use client";

import { useState, useEffect } from "react";

export type ScrollDirection = "up" | "down" | null;

interface UseScrollDirectionOptions {
  /**
   * Minimum scroll distance (in px) to trigger direction change.
   * Higher values make scroll detection less sensitive.
   * Default: 50
   */
  threshold?: number;
  /**
   * Target element to observe for scroll events.
   * If not provided, defaults to window scroll.
   */
  target?: HTMLElement | null;
}

/**
 * Hook to detect scroll direction on a target element or the window.
 * Returns "down" when scrolling down, "up" when scrolling up, or null initially.
 *
 * @param options.threshold - Minimum scroll distance to trigger direction change (default: 50)
 * @param options.target - Target element to observe (default: window)
 */
export function useScrollDirection({
  threshold = 50,
  target,
}: UseScrollDirectionOptions = {}) {
  const [scrollDirection, setScrollDirection] = useState<ScrollDirection>(null);

  useEffect(() => {
    // Determine scroll target and get initial scroll position
    const scrollTarget = target ?? window;
    const getScrollY = () =>
      target ? target.scrollTop : window.scrollY;

    let lastScrollY = getScrollY();
    let ticking = false;

    const updateScrollDirection = () => {
      const scrollY = getScrollY();

      if (Math.abs(scrollY - lastScrollY) < threshold) {
        ticking = false;
        return;
      }

      setScrollDirection(scrollY > lastScrollY ? "down" : "up");
      lastScrollY = scrollY > 0 ? scrollY : 0;
      ticking = false;
    };

    const onScroll = () => {
      if (!ticking) {
        window.requestAnimationFrame(updateScrollDirection);
        ticking = true;
      }
    };

    scrollTarget.addEventListener("scroll", onScroll, { passive: true });

    return () => {
      scrollTarget.removeEventListener("scroll", onScroll);
    };
  }, [threshold, target]);

  return scrollDirection;
}
