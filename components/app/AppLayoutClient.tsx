"use client";

import type { ReactNode } from "react";
import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { supabase } from "@/lib/supabase/browser";
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { logSessionRefresh } from "@/lib/auth/session-telemetry";
import { NavigationFeedbackProvider } from "./navigation-feedback";
import { ScrollProvider } from "@/lib/contexts/ScrollContext";
import { TopHeader } from "./TopHeader";
import { NavBar } from "./NavBar";
import type { SharedUser } from "@/data-access/sharing";

type AppLayoutClientProps = {
  children: ReactNode;
  userName: string;
  avatarUrl?: string | null;
  sharers?: SharedUser[];
};

export function AppLayoutClient({
  children,
  userName,
  avatarUrl,
  sharers,
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
        // Use getUser() instead of getSession() - it validates with the server
        // and doesn't trigger the Supabase security warning
        const { data, error } = await withRefreshLock(() => supabase.auth.getUser());
        const duration = performance.now() - startTime;

        if (error || !data.user) {
          console.error("[SUPABASE] Initial session check failed:", error);
          logSessionRefresh("session_refresh_failure", "initial", {
            attempt_id: attemptId,
            error: error || new Error("no_session"),
            duration_ms: duration
          });
        } else {
          console.log("[SUPABASE] Initial session OK:", !!data.user);
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
    <ScrollProvider threshold={50}>
      <NavigationFeedbackProvider>
        <LayoutContent userName={userName} avatarUrl={avatarUrl} sharers={sharers}>
          {children}
        </LayoutContent>
      </NavigationFeedbackProvider>
    </ScrollProvider>
  );
}

function LayoutContent({
  children,
  userName,
  avatarUrl,
  sharers,
}: AppLayoutClientProps) {
  return (
    <div className="flex flex-col h-dvh overflow-hidden">
      <TopHeader userName={userName} avatarUrl={avatarUrl} sharers={sharers} />
      <main className="flex-1 min-h-0">
        {children}
      </main>
      <NavBar />
    </div>
  );
}
