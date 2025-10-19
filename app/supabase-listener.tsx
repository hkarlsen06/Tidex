"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

import { supabase } from "@/lib/supabase/browser";

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

  return null;
}
