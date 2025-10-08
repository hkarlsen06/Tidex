"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import type { Session } from "@supabase/supabase-js";

import { createSupabaseBrowserClient } from "@/lib/supabase/client";

type SupabaseListenerProps = {
  accessToken?: string;
};

export function SupabaseListener({ accessToken }: SupabaseListenerProps) {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  useEffect(() => {
    // HMR guard: prevent duplicate subscriptions during hot module reload in dev
    if ((window as any).__sbAuthSub) return;

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event: string, session: Session | null) => {
      // Global auth event logging for debugging
      console.log(`[SUPABASE AUTH] ${event}`, {
        hasSession: !!session,
        userId: session?.user?.id,
        timestamp: new Date().toISOString(),
      });

      if (session?.access_token !== accessToken) {
        router.refresh();
      }
    });

    (window as any).__sbAuthSub = true;

    return () => {
      subscription.unsubscribe();
      (window as any).__sbAuthSub = false;
    };
  }, [accessToken, router, supabase]);

  return null;
}
