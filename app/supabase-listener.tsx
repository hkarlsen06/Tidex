"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

import { supabase } from "@/lib/supabase/browser";
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { isIAPAvailable, syncAppleSubscription } from "@/lib/capacitor/iap";

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

  // Refresh session when app becomes visible again
  // Critical for PWA: When user switches back to app after >1 hour,
  // this triggers token refresh before any API calls fail
  useEffect(() => {
    const handleVisibilityChange = async () => {
      if (document.visibilityState === "visible") {
        try {
          await withRefreshLock(() => supabase.auth.getUser());

          // For iOS: Sync Apple subscription state on foreground
          // This catches upgrades/downgrades made via App Store Settings
          // which would otherwise take 2-3 min to arrive via Apple's webhook
          if (isIAPAvailable()) {
            const syncResult = await syncAppleSubscription();
            if (syncResult.synced) {
              // Subscription was verified with Apple - refresh to show updated state
              router.refresh();
            }
          }
        } catch {
          // Silently handle refresh errors
        }
      }
    };

    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => document.removeEventListener("visibilitychange", handleVisibilityChange);
  }, [router]);

  // iOS Safari PWA fallback - pageshow event
  // iOS Safari fires pageshow when restoring from bfcache (back/forward cache)
  useEffect(() => {
    const handlePageShow = async (event: PageTransitionEvent) => {
      if (event.persisted) {
        try {
          await withRefreshLock(() => supabase.auth.getUser());

          // For iOS: Sync Apple subscription state
          if (isIAPAvailable()) {
            const syncResult = await syncAppleSubscription();
            if (syncResult.synced) {
              router.refresh();
            }
          }
        } catch {
          // Silently handle refresh errors
        }
      }
    };

    window.addEventListener("pageshow", handlePageShow);
    return () => window.removeEventListener("pageshow", handlePageShow);
  }, [router]);

  return null;
}
