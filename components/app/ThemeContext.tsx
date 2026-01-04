"use client";

import { createContext, useContext, useLayoutEffect, useState, useRef, useCallback, ReactNode } from "react";
import { updateTheme as updateThemeAction } from "@/app/actions/updateTheme";

type Theme = "light" | "dark" | "system";
type EffectiveTheme = "light" | "dark";

interface ThemeContextType {
  theme: EffectiveTheme;
  toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

/**
 * Detect if running in iOS native app (Capacitor WebView)
 * iOS WKWebView doesn't have Safari in user agent when embedded
 */
function isIOSNative(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent || "";
  return /iPhone|iPad|iPod/.test(ua) && !/Safari/.test(ua);
}

export function ThemeProvider({
  children
}: {
  children: ReactNode;
}) {
  const [theme, setTheme] = useState<EffectiveTheme>("dark");
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isNativeRef = useRef<boolean>(false);

  // Use useLayoutEffect to apply theme synchronously before browser paint
  // localStorage is used as source of truth (synced to DB on change)
  // On native iOS, always follow system preference (user can't toggle theme)
  useLayoutEffect(() => {
    const isNative = isIOSNative();
    isNativeRef.current = isNative;

    // On native iOS, always use system preference
    // On web, use localStorage or default to system preference
    const savedTheme = isNative ? null : (localStorage.getItem("theme") as Theme | null);
    const themePreference: Theme = savedTheme || "system";

    // Resolve "system" to actual light/dark
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    let effectiveTheme: EffectiveTheme;
    if (themePreference === "system") {
      effectiveTheme = prefersDark ? "dark" : "light";
    } else {
      effectiveTheme = themePreference;
    }

    // On native iOS, the launch screen is always dark
    // If system is in light mode, we need to transition smoothly
    // The inline script already set dark mode, so only update if different
    const currentIsDark = document.documentElement.classList.contains("dark");
    const needsTransition = isNative && currentIsDark && effectiveTheme === "light";

    if (needsTransition) {
      // Delay the theme switch slightly to allow content to render first
      // This makes the dark-to-light transition less jarring
      requestAnimationFrame(() => {
        setTheme(effectiveTheme);
        document.documentElement.classList.toggle("dark", effectiveTheme === "dark");
      });
    } else {
      // Sync theme state with DOM immediately
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setTheme(effectiveTheme);
      document.documentElement.classList.toggle("dark", effectiveTheme === "dark");
    }

    // Listen for system theme changes if using system preference (including all native)
    if (themePreference === "system" || isNative) {
      const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
      const handleChange = (e: MediaQueryListEvent) => {
        const newTheme: EffectiveTheme = e.matches ? "dark" : "light";
        setTheme(newTheme);
        document.documentElement.classList.toggle("dark", e.matches);
      };
      mediaQuery.addEventListener("change", handleChange);
      return () => mediaQuery.removeEventListener("change", handleChange);
    }
  }, []);

  // Cleanup debounce timer on unmount
  useLayoutEffect(() => {
    return () => {
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
    };
  }, []);

  const toggleTheme = useCallback(() => {
    const newTheme: EffectiveTheme = theme === "dark" ? "light" : "dark";
    setTheme(newTheme);
    localStorage.setItem("theme", newTheme);
    document.documentElement.classList.toggle("dark", newTheme === "dark");

    // Debounce database sync to prevent multiple requests on rapid toggling
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
    }

    debounceTimerRef.current = setTimeout(() => {
      updateThemeAction(newTheme).catch((err) => {
        console.error("Failed to sync theme to database:", err);
      });
    }, 1000); // Wait 1 second after last toggle before syncing to DB
  }, [theme]);

  return (
    <ThemeContext.Provider value={{ theme, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  const context = useContext(ThemeContext);
  if (context === undefined) {
    throw new Error("useTheme must be used within a ThemeProvider");
  }
  return context;
}
