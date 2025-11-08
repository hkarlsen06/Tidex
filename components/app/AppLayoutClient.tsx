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

  // Proactively prefetch common routes to speed up transitions
  useEffect(() => {
    try {
      router.prefetch("/");
      router.prefetch("/shifts");
      router.prefetch("/stats");
      router.prefetch("/settings");
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
    <>
      <TopHeader userName={userName} avatarUrl={avatarUrl} />
      <main className="flex items-center min-h-dvh pt-[calc(3.75rem+env(safe-area-inset-top))] pb-[calc(5rem+env(safe-area-inset-bottom))] md:pt-20 md:pb-20">
        <div className="mx-auto max-w-md px-4 w-full">
          {children}
        </div>
      </main>
      <NavBar />
    </>
  );
}
