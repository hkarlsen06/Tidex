"use client";

import {
  createContext,
  startTransition,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { usePathname, useRouter } from "next/navigation";

type NavigationFeedbackContextValue = {
  navigate: (href: string) => void;
  pendingPath: string | null; // Pathname only (no query/hash)
};

const NavigationFeedbackContext =
  createContext<NavigationFeedbackContextValue | null>(null);

export function NavigationFeedbackProvider({
  children,
}: {
  children: ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [pendingPath, setPendingPath] = useState<string | null>(null);

  const toPathname = useCallback((href: string) => {
    try {
      const url = new URL(href, window.location.origin);
      const path = url.pathname;
      // Treat "/" as "/dashboard" for consistent comparison
      if (path === "/") return "/dashboard";
      return path.replace(/\/+$/, "");
    } catch {
      // Fallback: strip query/hash manually
      const pathOnly = href.split("?")[0].split("#")[0];
      // Treat "/" as "/dashboard" for consistent comparison
      if (pathOnly === "/") return "/dashboard";
      return pathOnly.replace(/\/+$/, "");
    }
  }, []);

  const navigate = useCallback(
    (href: string) => {
      // Ignore navigation if we're already on the target path
      if (!href) {
        return;
      }

      const targetPath = toPathname(href);
      if (targetPath === toPathname(pathname)) {
        return;
      }

      setPendingPath(targetPath);
      router.push(href);
    },
    [pathname, router, toPathname],
  );

  // ALWAYS clear pendingPath when pathname changes.
  // This is intentionally simple and handles ALL cases:
  // - Normal navigation completing (pathname reaches pendingPath)
  // - Deeplinks from push notifications (pathname changes externally)
  // - Login/logout redirects (pathname changes to auth pages or dashboard)
  // - Interrupted navigation (something else happened)
  //
  // The navbar will then correctly highlight based on the actual pathname.
  // If there's a new navigation, pendingPath will be set again by navigate().
  useEffect(() => {
    startTransition(() => {
      setPendingPath(null);
    });
  }, [pathname]);

  const value = useMemo(
    () => ({
      navigate,
      pendingPath,
    }),
    [navigate, pendingPath],
  );

  return (
    <NavigationFeedbackContext.Provider value={value}>
      {children}
    </NavigationFeedbackContext.Provider>
  );
}

export function useNavigationFeedback() {
  const context = useContext(NavigationFeedbackContext);
  if (!context) {
    throw new Error(
      "useNavigationFeedback must be used within a NavigationFeedbackProvider",
    );
  }
  return context;
}
