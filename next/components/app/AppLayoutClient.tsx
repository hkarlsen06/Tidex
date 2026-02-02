"use client";

import type { ReactNode } from "react";
import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { supabase } from "@/lib/supabase/browser";
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { NavigationFeedbackProvider } from "./navigation-feedback";
import { ScrollProvider } from "@/lib/contexts/ScrollContext";
import { AddShiftFormProvider } from "@/lib/contexts/AddShiftFormContext";
import { RouteVisibilityProvider } from "./RouteVisibilityContext";
import { NativeTabBarProvider } from "@/lib/contexts/NativeTabBarContext";
import { TopHeader } from "./TopHeader";
import { NavBar } from "./NavBar";
import { NativeTabBarSync } from "./NativeTabBarSync";
import { ShowNativeTabBar } from "./ShowNativeTabBar";

type AppLayoutClientProps = {
  children: ReactNode;
  userName: string;
};

export function AppLayoutClient({
  children,
  userName,
}: AppLayoutClientProps) {
  const router = useRouter();

  // Optimized prefetch: Only prefetch critical routes
  // Stats page is heavy (recharts) - let it lazy load on demand
  // Settings routes are prefetched on hover via Link components
  useEffect(() => {
    try {
      router.prefetch("/dashboard");
      router.prefetch("/shifts");
    } catch {
      // Ignore if prefetch isn't available in this environment
    }
  }, [router]);

  // Initial session check on app mount
  // Ensures session is fresh on cold start (e.g., after device restart)
  useEffect(() => {
    const checkInitialSession = async () => {
      try {
        await withRefreshLock(() => supabase.auth.getClaims());
      } catch {
        // Silently handle session check errors
      }
    };

    checkInitialSession();
  }, []);

  return (
    <NativeTabBarProvider>
      <RouteVisibilityProvider>
        <ScrollProvider threshold={50}>
          <AddShiftFormProvider>
            <NavigationFeedbackProvider>
              <LayoutContent userName={userName}>
                {children}
              </LayoutContent>
            </NavigationFeedbackProvider>
          </AddShiftFormProvider>
          <NativeTabBarSync />
          <ShowNativeTabBar />
        </ScrollProvider>
      </RouteVisibilityProvider>
    </NativeTabBarProvider>
  );
}

function LayoutContent({
  children,
  userName,
}: AppLayoutClientProps) {
  return (
    <div className="flex flex-col h-dvh">
      <TopHeader userName={userName} />
      <main className="flex-1 min-h-0 overflow-hidden">
        {children}
      </main>
      <NavBar />
    </div>
  );
}
