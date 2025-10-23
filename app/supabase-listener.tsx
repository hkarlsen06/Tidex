"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

import { supabase } from "@/lib/supabase/browser";
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { logSessionRefresh, hasAuthCookie, shouldAttemptWakeRefresh } from "@/lib/auth/session-telemetry";

type SupabaseListenerProps = {
  accessToken?: string;
};

export function SupabaseListener({ accessToken }: SupabaseListenerProps) {
  const router = useRouter();
  const previousAccessTokenRef = useRef<string | null>(accessToken ?? null);

  useEffect(() => {
    previousAccessTokenRef.current = accessToken ?? null;
  }, [accessToken]);

  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      const nextAccessToken = session?.access_token ?? null;

      if (nextAccessToken !== previousAccessTokenRef.current) {
        previousAccessTokenRef.current = nextAccessToken;
        router.refresh();
      }
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [router]);

  // Løsning 1: Refresh session when app becomes visible again
  // Critical for PWA: When user switches back to app after >1 hour,
  // this triggers token refresh before any API calls fail
  useEffect(() => {
    const handleVisibilityChange = async () => {
      if (document.visibilityState === "visible") {
        console.log("[SUPABASE] App visible - checking session");

        // Debounce: Skip if another wake event fired recently
        if (!shouldAttemptWakeRefresh("visibilitychange")) {
          return;
        }

        // Check if auth cookie exists before attempting refresh
        if (!hasAuthCookie()) {
          console.log("[SUPABASE] No auth cookie found - skipping refresh");
          logSessionRefresh("session_refresh_skipped_no_cookie", "visibilitychange");
          return;
        }

        const startTime = performance.now();
        const attemptId = logSessionRefresh("session_refresh_attempt", "visibilitychange");

        try {
          await withRefreshLock(() => supabase.auth.getSession());
          const duration = performance.now() - startTime;
          logSessionRefresh("session_refresh_success", "visibilitychange", { attempt_id: attemptId, duration_ms: duration });
        } catch (error) {
          const duration = performance.now() - startTime;
          console.error("[SUPABASE] Failed to refresh on wake:", error);
          logSessionRefresh("session_refresh_failure", "visibilitychange", { attempt_id: attemptId, error, duration_ms: duration });
        }
      }
    };

    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => document.removeEventListener("visibilitychange", handleVisibilityChange);
  }, []);

  // Løsning 2a: iOS Safari PWA fallback - pageshow event
  // iOS Safari fires pageshow when restoring from bfcache (back/forward cache)
  // More reliable than visibilitychange in some iOS versions
  useEffect(() => {
    const handlePageShow = async (event: PageTransitionEvent) => {
      if (event.persisted) {
        console.log("[SUPABASE] App restored from cache - checking session");

        // Debounce: Skip if another wake event fired recently
        if (!shouldAttemptWakeRefresh("pageshow")) {
          return;
        }

        // Check if auth cookie exists before attempting refresh
        if (!hasAuthCookie()) {
          console.log("[SUPABASE] No auth cookie found - skipping refresh");
          logSessionRefresh("session_refresh_skipped_no_cookie", "pageshow");
          return;
        }

        const startTime = performance.now();
        const attemptId = logSessionRefresh("session_refresh_attempt", "pageshow");

        try {
          await withRefreshLock(() => supabase.auth.getSession());
          const duration = performance.now() - startTime;
          logSessionRefresh("session_refresh_success", "pageshow", { attempt_id: attemptId, duration_ms: duration });
        } catch (error) {
          const duration = performance.now() - startTime;
          console.error("[SUPABASE] Failed to refresh on pageshow:", error);
          logSessionRefresh("session_refresh_failure", "pageshow", { attempt_id: attemptId, error, duration_ms: duration });
        }
      }
    };

    window.addEventListener("pageshow", handlePageShow);
    return () => window.removeEventListener("pageshow", handlePageShow);
  }, []);

  // Løsning 2b: iOS Safari PWA fallback - focus event
  // Additional fallback for iOS standalone mode where visibilitychange may not fire
  // Uses 'once' to avoid spamming refresh on every focus
  useEffect(() => {
    let hasFiredOnce = false;
    const timers = new Set<ReturnType<typeof setTimeout>>();

    const handleFocus = async () => {
      if (hasFiredOnce) return;
      hasFiredOnce = true;

      console.log("[SUPABASE] Window focused - checking session");

      // Debounce: Skip if another wake event fired recently
      if (!shouldAttemptWakeRefresh("focus")) {
        // Still reset flag to allow future checks
        const timer = setTimeout(() => {
          hasFiredOnce = false;
          timers.delete(timer);
        }, 5000);
        timers.add(timer);
        return;
      }

      // Check if auth cookie exists before attempting refresh
      if (!hasAuthCookie()) {
        console.log("[SUPABASE] No auth cookie found - skipping refresh");
        logSessionRefresh("session_refresh_skipped_no_cookie", "focus");
        // Still reset flag to allow future checks
        const timer = setTimeout(() => {
          hasFiredOnce = false;
          timers.delete(timer);
        }, 5000);
        timers.add(timer);
        return;
      }

      const startTime = performance.now();
      const attemptId = logSessionRefresh("session_refresh_attempt", "focus");

      try {
        await withRefreshLock(() => supabase.auth.getSession());
        const duration = performance.now() - startTime;
        logSessionRefresh("session_refresh_success", "focus", { attempt_id: attemptId, duration_ms: duration });
      } catch (error) {
        const duration = performance.now() - startTime;
        console.error("[SUPABASE] Failed to refresh on focus:", error);
        logSessionRefresh("session_refresh_failure", "focus", { attempt_id: attemptId, error, duration_ms: duration });
      }

      // Reset flag after 5 seconds to allow future focus events
      const timer = setTimeout(() => {
        hasFiredOnce = false;
        timers.delete(timer);
      }, 5000);
      timers.add(timer);
    };

    window.addEventListener("focus", handleFocus);
    return () => {
      window.removeEventListener("focus", handleFocus);
      timers.forEach((timer) => clearTimeout(timer));
      timers.clear();
    };
  }, []);

  return null;
}
