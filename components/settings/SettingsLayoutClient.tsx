"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { SettingsNav } from "./SettingsNav";
import { SettingsBackButton } from "./SettingsBackButton";

export function SettingsLayoutClient({ children }: { children: ReactNode }) {
  const pathname = usePathname();

  // Normalize pathname to remove locale prefix
  const normalizedPath = pathname.replace(/^\/(en|no)/, "").replace(/\/$/, "");

  // Check if we're on the settings landing page
  const isLandingPage = normalizedPath === "/settings";

  // If on landing page, render children without sidebar
  if (isLandingPage) {
    return <>{children}</>;
  }

  // On deep routes, show sidebar layout
  return (
    <>
      {/* Mobile/Tablet: Back button (hidden on desktop where sidebar is visible) */}
      <div className="container mx-auto max-w-2xl pt-4 lg:hidden">
        <SettingsBackButton />
      </div>

      {/* Mobile/Tablet: vertical stack. Desktop: side-by-side, break out of parent container */}
      <div className="flex w-full flex-col lg:relative lg:left-1/2 lg:right-1/2 lg:-ml-[50vw] lg:-mr-[50vw] lg:w-screen lg:flex-row lg:gap-0 lg:px-0 lg:items-start lg:pt-6">
        {/* Navigation Sidebar - Left side, sticky on desktop */}
        <div className="hidden lg:flex lg:w-1/3 lg:shrink-0 lg:sticky lg:top-22 lg:z-40 lg:justify-end lg:pr-6">
          <div className="w-full max-w-[320px]">
            <SettingsNav />
          </div>
        </div>

        {/* Content Section - Right side, scrollable on desktop */}
        <div className="lg:w-2/3 lg:flex lg:justify-start lg:pl-6">
          <div className="w-full lg:max-w-[680px]">
            {children}
          </div>
        </div>
      </div>
    </>
  );
}
