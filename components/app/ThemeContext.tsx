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

export function ThemeProvider({
  serverTheme,
  children
}: {
  serverTheme?: Theme | null;
  children: ReactNode;
}) {
  const [theme, setTheme] = useState<EffectiveTheme>("dark");
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Use useLayoutEffect to apply theme synchronously before browser paint
  // This minimizes flash when serverTheme differs from localStorage
  useLayoutEffect(() => {
    // Priority: serverTheme (DB) > localStorage > system preference
    let effectiveTheme: EffectiveTheme;
    let themePreference: Theme;

    if (serverTheme) {
      // User is authenticated and has a theme preference in DB
      themePreference = serverTheme;
      // Sync to localStorage for consistency with inline script on next load
      localStorage.setItem("theme", themePreference);
    } else {
      // User is not authenticated or no DB preference - use localStorage or default to system
      const savedTheme = localStorage.getItem("theme") as Theme | null;
      themePreference = savedTheme || "system";
    }

    // Resolve "system" to actual light/dark
    if (themePreference === "system") {
      const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
      effectiveTheme = prefersDark ? "dark" : "light";
    } else {
      effectiveTheme = themePreference;
    }

    setTheme(effectiveTheme);
    document.documentElement.classList.toggle("dark", effectiveTheme === "dark");

    // Listen for system theme changes if using system preference
    if (themePreference === "system") {
      const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
      const handleChange = (e: MediaQueryListEvent) => {
        const newTheme: EffectiveTheme = e.matches ? "dark" : "light";
        setTheme(newTheme);
        document.documentElement.classList.toggle("dark", e.matches);
      };
      mediaQuery.addEventListener("change", handleChange);
      return () => mediaQuery.removeEventListener("change", handleChange);
    }
  }, [serverTheme]);

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
