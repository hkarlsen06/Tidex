"use client";

import { useState, useEffect } from "react";

const MOBILE_BREAKPOINT = 640; // sm breakpoint in Tailwind

/**
 * Hook to detect if the current viewport is mobile-sized.
 * Uses 640px (sm breakpoint) as the threshold.
 */
export function useIsMobile(): boolean {
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const checkMobile = () => {
      setIsMobile(window.innerWidth < MOBILE_BREAKPOINT);
    };

    // Check initially
    checkMobile();

    // Listen for resize events
    window.addEventListener("resize", checkMobile);
    return () => window.removeEventListener("resize", checkMobile);
  }, []);

  return isMobile;
}
