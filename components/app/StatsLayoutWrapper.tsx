"use client";

import type { ReactNode } from "react";

/**
 * Stats layout wrapper that breaks out of the parent container constraints on desktop
 * while maintaining mobile container behavior.
 */
export function StatsLayoutWrapper({ children }: { children: ReactNode }) {
  return (
    <div className="md:relative md:left-1/2 md:right-1/2 md:-ml-[50vw] md:-mr-[50vw] md:w-screen md:-mx-4">
      <div className="md:mx-auto md:max-w-6xl md:px-6">
        {children}
      </div>
    </div>
  );
}
