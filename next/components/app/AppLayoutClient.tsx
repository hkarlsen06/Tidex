"use client";

import type { ReactNode } from "react";
import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { motion, spring, useReducedMotion } from "motion/react";

import { supabase } from "@/lib/supabase/browser";
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { NavigationFeedbackProvider } from "./navigation-feedback";
import { ScrollProvider } from "@/lib/contexts/ScrollContext";
import { AddShiftFormProvider } from "@/lib/contexts/AddShiftFormContext";
import { RouteVisibilityProvider } from "./RouteVisibilityContext";
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
      router.prefetch("/dashboard");
      router.prefetch("/shifts");
    } catch {
      // Ignore if prefetch isn't available in this environment
    }
  }, [router]);

  // Initial session check on app mount
  // Ensures session is fresh on cold start (e.g., after device restart)
  useEffect(() => {
    const checkInitialSession = async () => {
      try {
        await withRefreshLock(() => supabase.auth.getClaims());
      } catch {
        // Silently handle session check errors
      }
    };

    checkInitialSession();
  }, []);

  return (
    <RouteVisibilityProvider>
      <ScrollProvider threshold={50}>
        <AddShiftFormProvider>
          <NavigationFeedbackProvider>
            <LayoutContent userName={userName}>
              {children}
            </LayoutContent>
          </NavigationFeedbackProvider>
        </AddShiftFormProvider>
      </ScrollProvider>
    </RouteVisibilityProvider>
  );
}

function LayoutContent({
  children,
  userName,
}: AppLayoutClientProps) {
  const pathname = usePathname();
  const shouldReduceMotion = useReducedMotion();

  const normalizedPath = pathname.replace(/^\/(no|en)(?=\/|$)/, "") || "/";
  const isTabRoute = [
    "/dashboard",
    "/shifts",
    "/shifts/add",
    "/stats",
    "/sharing",
  ].some((prefix) => normalizedPath === prefix || normalizedPath.startsWith(`${prefix}/`));

  return (
    <div className="flex flex-col h-dvh">
      <TopHeader userName={userName} />
      <main className="flex-1 min-h-0 overflow-hidden">
        {isTabRoute ? (
          <motion.div
            key={normalizedPath}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={shouldReduceMotion ? { duration: 0 } : { type: spring, visualDuration: 0.34, bounce: 0.16 }}
            style={{ height: "100%" }}
          >
            {children}
          </motion.div>
        ) : (
          children
        )}
      </main>
      <NavBar />
    </div>
  );
}
