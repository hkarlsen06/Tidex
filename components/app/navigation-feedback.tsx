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
import { IconLoader } from "@tabler/icons-react";

type NavigationFeedbackContextValue = {
  navigate: (href: string) => void;
  pendingPath: string | null; // Pathname only (no query/hash)
  isNavigating: boolean;
};

const NavigationFeedbackContext = createContext<NavigationFeedbackContextValue | null>(null);

export function NavigationFeedbackProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [pendingPath, setPendingPath] = useState<string | null>(null);
  const [isNavigating, setIsNavigating] = useState(false);
  const hideFrameRef = useRef<number | null>(null);
  const showDelayRef = useRef<number | null>(null);

  const toPathname = useCallback((href: string) => {
    try {
      const url = new URL(href, window.location.origin);
      const path = url.pathname;
      if (path === "/") return "/";
      return path.replace(/\/+$/, "");
    } catch {
      // Fallback: strip query/hash manually
      const pathOnly = href.split("?")[0].split("#")[0];
      if (pathOnly === "/") return "/";
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
      // Delay showing the overlay to avoid flashing on fast (prefetched) transitions
      if (showDelayRef.current) {
        window.clearTimeout(showDelayRef.current);
        showDelayRef.current = null;
      }
      showDelayRef.current = window.setTimeout(() => {
        setIsNavigating(true);
        showDelayRef.current = null;
      }, 150);

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
      setIsNavigating(false);
      hideFrameRef.current = null;
    });

    return () => {
      if (hideFrameRef.current) {
        window.cancelAnimationFrame(hideFrameRef.current);
        hideFrameRef.current = null;
      }
      if (showDelayRef.current) {
        window.clearTimeout(showDelayRef.current);
        showDelayRef.current = null;
      }
    };
  }, [pathname, pendingPath]);

  // Ensure we never leave the overlay hanging forever if the navigation fails
  useEffect(() => {
    if (!isNavigating) {
      return;
    }

    const timeout = window.setTimeout(() => {
      setIsNavigating(false);
      setPendingPath(null);
    }, 6000);

    return () => window.clearTimeout(timeout);
  }, [isNavigating]);

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
      isNavigating,
    }),
    [navigate, pendingPath, isNavigating],
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

export function NavigationOverlay() {
  const { isNavigating, pendingPath } = useNavigationFeedback();

  // Hide the full-screen overlay for main tab navigations
  const skipOverlayFor = new Set(["/", "/shifts", "/stats", "/settings"]);
  const skip = pendingPath && skipOverlayFor.has(pendingPath);

  if (!isNavigating || skip) {
    return null;
  }

  return (
    <div
      role="status"
      aria-live="polite"
      aria-busy="true"
      aria-label="Loading next page"
      className="fixed inset-0 z-30 flex items-center justify-center bg-background transition-colors"
    >
      <IconLoader className="h-12 w-12 animate-spin text-text-primary" stroke={2} />
    </div>
  );
}
