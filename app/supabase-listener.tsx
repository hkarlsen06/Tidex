"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import type { Session } from "@supabase/supabase-js";

import { createSupabaseBrowserClient } from "@/lib/supabase/client";
import { AUTH_SYNC_CSRF_HEADER } from "@/lib/auth/constants";
import {
  ensureAuthSyncCsrfToken,
  getAuthSyncCsrfToken,
} from "@/lib/auth/csrf.client";

type SupabaseListenerProps = {
  accessToken?: string;
};

export function SupabaseListener({ accessToken }: SupabaseListenerProps) {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();
  const registered = useRef(false);
  const csrfTokenRef = useRef<string | null>(null);

  useEffect(() => {
    // Ensure only one subscription is ever registered, even across strict mode double-renders
    if (registered.current) return;
    registered.current = true;

    console.log("[SUPABASE LISTENER] Mounting single auth state listener");

    const ensureCsrfToken = () => {
      const existing = getAuthSyncCsrfToken();
      if (existing) {
        csrfTokenRef.current = existing;
        return existing;
      }

      const fresh = ensureAuthSyncCsrfToken();
      csrfTokenRef.current = fresh;
      return fresh;
    };

    ensureCsrfToken();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(async (event: string, session: Session | null) => {
      // Global auth event logging for debugging
      console.log(`[SUPABASE AUTH] ${event}`, {
        hasSession: !!session,
        userId: session?.user?.id,
        timestamp: new Date().toISOString(),
      });

      // Sync auth state changes to server-side cookies to prevent "Invalid Refresh Token" errors
      try {
        const csrfToken = csrfTokenRef.current ?? ensureCsrfToken();

        await fetch("/auth/callback", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            [AUTH_SYNC_CSRF_HEADER]: csrfToken,
          },
          body: JSON.stringify({ event, session }),
          keepalive: true, // Ensure request completes even if tab closes or navigates
          cache: "no-store", // Prevent service worker or browser caching
        });
      } catch (error) {
        console.error("[AUTH SYNC] Failed to sync session:", error);
      }

      // Refresh server components to reflect new auth state
      if (session?.access_token !== accessToken) {
        router.refresh();
      }
    });

    return () => {
      subscription.unsubscribe();
      registered.current = false;
    };
  }, [accessToken, router, supabase]);

  return null;
}
