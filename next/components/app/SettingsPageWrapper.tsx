"use client";

import type { ReactNode } from "react";
import { ScrollablePageWrapper } from "./ScrollablePageWrapper";

interface SettingsPageWrapperProps {
  children: ReactNode;
  /**
   * Unique key for scroll restoration. Defaults to "settings-sub".
   */
  routeKey?: string;
  /**
   * If true, disables scroll restoration - page always starts at top.
   */
  disableScrollRestoration?: boolean;
}

/**
 * Wrapper for settings sub-pages that provides scrolling and consistent layout.
 * Use this for all /settings/* pages that need scrollable content.
 */
export function SettingsPageWrapper({
  children,
  routeKey = "settings-sub",
  disableScrollRestoration = false,
}: SettingsPageWrapperProps) {
  return (
    <ScrollablePageWrapper routeKey={routeKey} disableScrollRestoration={disableScrollRestoration}>
      <div className="py-8">
        {children}
      </div>
    </ScrollablePageWrapper>
  );
}
