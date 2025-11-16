"use client";

import type { ReactNode } from "react";
import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { supabase } from "@/lib/supabase/browser";
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { logSessionRefresh } from "@/lib/auth/session-telemetry";
import { NavigationFeedbackProvider } from "./navigation-feedback";
import { TopHeader } from "./TopHeader";
import { NavBar } from "./NavBar";

type AppLayoutClientProps = {
  children: ReactNode;
  userName: string;
  avatarUrl?: string | null;
};

export function AppLayoutClient({
  children,
  userName,
  avatarUrl,
}: AppLayoutClientProps) {
  const router = useRouter();

  // Optimized prefetch: Only prefetch critical routes
  // Stats page is heavy (recharts) - let it lazy load on demand
  // Settings routes are prefetched on hover via Link components
  useEffect(() => {
    try {
      router.prefetch("/");
      router.prefetch("/shifts");
    } catch {
      // Ignore if prefetch isn't available in this environment
    }
  }, [router]);

  // Løsning 4: Initial session check on app mount
  // Ensures session is fresh on cold start (e.g., after device restart)
  // Prevents flashing of stale state before first API call
  useEffect(() => {
    const checkInitialSession = async () => {
      const startTime = performance.now();
      const attemptId = logSessionRefresh("session_refresh_attempt", "initial");

      try {
        const { data, error } = await withRefreshLock(() => supabase.auth.getSession());
        const duration = performance.now() - startTime;

        if (error || !data.session) {
          console.error("[SUPABASE] Initial session check failed:", error);
          logSessionRefresh("session_refresh_failure", "initial", {
            attempt_id: attemptId,
            error: error || new Error("no_session"),
            duration_ms: duration
          });
        } else {
          console.log("[SUPABASE] Initial session OK:", !!data.session);
          logSessionRefresh("session_refresh_success", "initial", { attempt_id: attemptId, duration_ms: duration });
        }
      } catch (err) {
        const duration = performance.now() - startTime;
        console.error("[SUPABASE] Session check threw:", err);
        logSessionRefresh("session_refresh_failure", "initial", { attempt_id: attemptId, error: err, duration_ms: duration });
      }
    };

    checkInitialSession();
  }, []);

  return (
    <NavigationFeedbackProvider>
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
    <div className="flex flex-col min-h-screen">
      <TopHeader userName={userName} avatarUrl={avatarUrl} />
      <main className="flex-1 flex items-center justify-center md:pb-8">
        <div className="mx-auto max-w-md md:max-w-lg px-4 w-full pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-0">
          {children}
        </div>
      </main>
      <NavBar />
    </div>
  );
}
