"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { usePathname, useRouter } from "next/navigation";

type NavigationFeedbackContextValue = {
  navigate: (href: string) => void;
  pendingPath: string | null; // Pathname only (no query/hash)
};

const NavigationFeedbackContext = createContext<NavigationFeedbackContextValue | null>(null);

export function NavigationFeedbackProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [pendingPath, setPendingPath] = useState<string | null>(null);
  const hideFrameRef = useRef<number | null>(null);

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

  useEffect(() => {
    if (!pendingPath || pathname !== pendingPath) {
      return;
    }

    hideFrameRef.current = window.requestAnimationFrame(() => {
      setPendingPath(null);
      hideFrameRef.current = null;
    });

    return () => {
      if (hideFrameRef.current) {
        window.cancelAnimationFrame(hideFrameRef.current);
        hideFrameRef.current = null;
      }
    };
  }, [pathname, pendingPath]);

  useEffect(() => {
    return () => {
      if (hideFrameRef.current) {
        window.cancelAnimationFrame(hideFrameRef.current);
      }
    };
  }, []);

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
    throw new Error("useNavigationFeedback must be used within a NavigationFeedbackProvider");
  }
  return context;
}
