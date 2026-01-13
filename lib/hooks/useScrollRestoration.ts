"use client";

import { useRef, useEffect } from "react";

/**
 * Hook to save and restore scroll position for a specific route.
 * Uses sessionStorage to persist scroll position across navigation.
 *
 * @param key - Unique identifier for the route (e.g., "home", "shifts", "stats")
 * @param options - Optional configuration
 * @param options.disabled - If true, skips restoration (always starts at top)
 * @returns A ref to attach to the scrollable container element
 */
export function useScrollRestoration(key: string, options?: { disabled?: boolean }) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const disabled = options?.disabled ?? false;

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;

    // Skip restoration if disabled - always start at top
    if (disabled) {
      el.scrollTop = 0;
      return;
    }

    // Restore scroll position on mount
    const saved = sessionStorage.getItem(`scroll-${key}`);
    if (saved) {
      const scrollTop = parseInt(saved, 10);
      if (!isNaN(scrollTop)) {
        el.scrollTop = scrollTop;
      }
    }

    // Save scroll position on scroll (debounced)
    let timeout: ReturnType<typeof setTimeout>;
    const handleScroll = () => {
      clearTimeout(timeout);
      timeout = setTimeout(() => {
        sessionStorage.setItem(`scroll-${key}`, el.scrollTop.toString());
      }, 100);
    };

    el.addEventListener("scroll", handleScroll, { passive: true });

    return () => {
      clearTimeout(timeout);
      el.removeEventListener("scroll", handleScroll);
    };
  }, [key]);

  return scrollRef;
}
