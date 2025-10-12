"use client";

import type { ReactNode } from "react";

import { NavigationFeedbackProvider, NavigationOverlay } from "./navigation-feedback";
import { TopHeader } from "./TopHeader";
import { NavBar } from "./NavBar";
import { OnboardingPromptModal } from "./OnboardingPromptModal";

type AppLayoutClientProps = {
  children: ReactNode;
  userName: string;
  avatarUrl?: string | null;
  showOnboardingPrompt?: boolean;
};

export function AppLayoutClient({ children, userName, avatarUrl, showOnboardingPrompt = false }: AppLayoutClientProps) {
  return (
    <NavigationFeedbackProvider>
      <OnboardingPromptModal shouldShow={showOnboardingPrompt} />
      <LayoutContent userName={userName} avatarUrl={avatarUrl}>
        {children}
      </LayoutContent>
    </NavigationFeedbackProvider>
  );
}

function LayoutContent({
  children,
  userName,
  avatarUrl,
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
      <NavBar />
    </div>
  );
}
