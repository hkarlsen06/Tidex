"use client";

import { useEffect } from "react";

type Theme = "light" | "dark" | "system";

export function ThemeProvider({ serverTheme }: { serverTheme?: Theme | null }) {
  useEffect(() => {
    // Priority: serverTheme (DB) > localStorage > system preference
    let effectiveTheme: "light" | "dark";
    let themePreference: Theme;

    if (serverTheme) {
      // User is authenticated and has a theme preference in DB
      themePreference = serverTheme;
      // Sync to localStorage for consistency
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

    document.documentElement.classList.toggle("dark", effectiveTheme === "dark");

    // Listen for system theme changes if using system preference
    if (themePreference === "system") {
      const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
      const handleChange = (e: MediaQueryListEvent) => {
        document.documentElement.classList.toggle("dark", e.matches);
      };
      mediaQuery.addEventListener("change", handleChange);
      return () => mediaQuery.removeEventListener("change", handleChange);
    }
  }, [serverTheme]);

  return null;
}
