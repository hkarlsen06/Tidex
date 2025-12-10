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
  children
}: {
  children: ReactNode;
}) {
  const [theme, setTheme] = useState<EffectiveTheme>("dark");
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Use useLayoutEffect to apply theme synchronously before browser paint
  // localStorage is used as source of truth (synced to DB on change)
  useLayoutEffect(() => {
    // Use localStorage or default to system preference
    const savedTheme = localStorage.getItem("theme") as Theme | null;
    const themePreference: Theme = savedTheme || "system";

    // Resolve "system" to actual light/dark
    let effectiveTheme: EffectiveTheme;
    if (themePreference === "system") {
      const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
      effectiveTheme = prefersDark ? "dark" : "light";
    } else {
      effectiveTheme = themePreference;
    }

    // Sync theme state with DOM and system preference
    // eslint-disable-next-line react-hooks/set-state-in-effect
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
