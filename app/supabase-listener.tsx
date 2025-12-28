"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

import { supabase } from "@/lib/supabase/browser";
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { logSessionRefresh, shouldAttemptWakeRefresh } from "@/lib/auth/session-telemetry";
import { isNativePlatform } from "@/lib/capacitor/platform";

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

        const startTime = performance.now();
        const attemptId = logSessionRefresh("session_refresh_attempt", "visibilitychange");

        try {
          // Use getUser() instead of getSession() - it validates with the server
          // and doesn't trigger the Supabase security warning
          const { data, error } = await withRefreshLock(() => supabase.auth.getUser());
          const duration = performance.now() - startTime;

          if (error || !data.user) {
            console.error("[SUPABASE] Failed to refresh on wake:", error);
            logSessionRefresh("session_refresh_failure", "visibilitychange", {
              attempt_id: attemptId,
              error: error || new Error("no_session"),
              duration_ms: duration
            });
          } else {
            logSessionRefresh("session_refresh_success", "visibilitychange", { attempt_id: attemptId, duration_ms: duration });
          }
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

        const startTime = performance.now();
        const attemptId = logSessionRefresh("session_refresh_attempt", "pageshow");

        try {
          // Use getUser() instead of getSession() - it validates with the server
          const { data, error } = await withRefreshLock(() => supabase.auth.getUser());
          const duration = performance.now() - startTime;

          if (error || !data.user) {
            console.error("[SUPABASE] Failed to refresh on pageshow:", error);
            logSessionRefresh("session_refresh_failure", "pageshow", {
              attempt_id: attemptId,
              error: error || new Error("no_session"),
              duration_ms: duration
            });
          } else {
            logSessionRefresh("session_refresh_success", "pageshow", { attempt_id: attemptId, duration_ms: duration });
          }
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

      const startTime = performance.now();
      const attemptId = logSessionRefresh("session_refresh_attempt", "focus");

      try {
        // Use getUser() instead of getSession() - it validates with the server
        const { data, error } = await withRefreshLock(() => supabase.auth.getUser());
        const duration = performance.now() - startTime;

        if (error || !data.user) {
          console.error("[SUPABASE] Failed to refresh on focus:", error);
          logSessionRefresh("session_refresh_failure", "focus", {
            attempt_id: attemptId,
            error: error || new Error("no_session"),
            duration_ms: duration
          });
        } else {
          logSessionRefresh("session_refresh_success", "focus", { attempt_id: attemptId, duration_ms: duration });
        }
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

  // Capacitor iOS: Handle custom scheme URL opens (tidex://auth/callback)
  // When OAuth returns via custom scheme, close the browser and redirect to HTTPS callback
  useEffect(() => {
    // Only run on native platforms
    if (!isNativePlatform()) return;

    let cleanup: (() => void) | undefined;

    const setupListener = async () => {
      try {
        // Dynamic import to avoid loading Capacitor on web
        const { App } = await import("@capacitor/app");
        const { Browser } = await import("@capacitor/browser");

        const listenerHandle = await App.addListener("appUrlOpen", async ({ url }) => {
          // TODO: Remove this log after verifying the handler fires correctly
          console.log("[CAPACITOR] appUrlOpen received:", url);

          // Check if this is our OAuth callback scheme
          if (url.startsWith("tidex://auth/callback")) {
            // Close the in-app browser overlay immediately
            try {
              await Browser.close();
              console.log("[CAPACITOR] Browser closed");
            } catch (e) {
              // Browser may already be closed, ignore
              console.log("[CAPACITOR] Browser.close() failed (may already be closed):", e);
            }

            // Parse the custom scheme URL
            const customUrl = new URL(url);

            // Build the HTTPS callback URL preserving all query params
            const httpsCallbackUrl = new URL("https://app.tidex.no/auth/callback");
            customUrl.searchParams.forEach((value, key) => {
              httpsCallbackUrl.searchParams.set(key, value);
            });

            console.log("[CAPACITOR] Redirecting to HTTPS callback:", httpsCallbackUrl.toString());

            // Small delay to ensure browser is fully closed before navigation
            setTimeout(() => {
              window.location.href = httpsCallbackUrl.toString();
            }, 100);
          }
        });

        cleanup = () => {
          listenerHandle.remove();
        };
      } catch (error) {
        console.warn("[CAPACITOR] Failed to setup appUrlOpen listener:", error);
      }
    };

    setupListener();

    return () => {
      cleanup?.();
    };
  }, []);

  return null;
}
