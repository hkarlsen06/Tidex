"use client";

import type { ReactNode } from "react";

import { NavigationFeedbackProvider, NavigationOverlay } from "./navigation-feedback";
import { TopHeader } from "./TopHeader";
import { NavBar } from "./NavBar";

type AppLayoutClientProps = {
  children: ReactNode;
  userName: string;
  avatarUrl?: string | null;
  showAddShiftHint?: boolean;
};

export function AppLayoutClient({
  children,
  userName,
  avatarUrl,
  showAddShiftHint,
}: AppLayoutClientProps) {
  return (
    <NavigationFeedbackProvider>
      <LayoutContent userName={userName} avatarUrl={avatarUrl} showAddShiftHint={showAddShiftHint}>
        {children}
      </LayoutContent>
    </NavigationFeedbackProvider>
  );
}

function LayoutContent({
  children,
  userName,
  avatarUrl,
  showAddShiftHint,
}: AppLayoutClientProps) {
  return (
    <div className="app-container grid min-h-dvh grid-rows-[auto_1fr]">
      <TopHeader userName={userName} avatarUrl={avatarUrl} />
      <main
        className="relative px-4 pt-8"
        style={{ paddingBottom: "calc(6rem + env(safe-area-inset-bottom))" }}
      >
        {children}
        <NavigationOverlay />
      </main>
      <NavBar showAddShiftHint={showAddShiftHint} />
    </div>
  );
}
