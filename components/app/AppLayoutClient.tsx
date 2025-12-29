"use client";

import type { ReactNode } from "react";
import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { supabase } from "@/lib/supabase/browser";
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { logSessionRefresh } from "@/lib/auth/session-telemetry";
import { NavigationFeedbackProvider } from "./navigation-feedback";
import { ScrollProvider } from "@/lib/contexts/ScrollContext";
import { AddShiftFormProvider } from "@/lib/contexts/AddShiftFormContext";
import { TopHeader } from "./TopHeader";
import { NavBar } from "./NavBar";

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
        // Use getClaims() for initial session check - it refreshes the session first
        // if the access token is about to expire, then validates the JWT.
        // This is faster than getUser() which always makes a network request.
        const { data, error } = await withRefreshLock(() => supabase.auth.getClaims());
        const duration = performance.now() - startTime;

        if (error || !data?.claims) {
          console.error("[SUPABASE] Initial session check failed:", error);
          logSessionRefresh("session_refresh_failure", "initial", {
            attempt_id: attemptId,
            error: error || new Error("no_session"),
            duration_ms: duration
          });
        } else {
          console.log("[SUPABASE] Initial session OK:", !!data.claims);
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
      <AddShiftFormProvider>
        <NavigationFeedbackProvider>
          <LayoutContent userName={userName}>
            {children}
          </LayoutContent>
        </NavigationFeedbackProvider>
      </AddShiftFormProvider>
    </ScrollProvider>
  );
}

function LayoutContent({
  children,
  userName,
}: AppLayoutClientProps) {
  return (
    <div className="flex flex-col h-dvh overflow-hidden">
      <TopHeader userName={userName} />
      <main className="flex-1 min-h-0">
        {children}
      </main>
      <NavBar />
    </div>
  );
}
