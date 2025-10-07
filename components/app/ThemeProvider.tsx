"use client";

import { useEffect } from "react";

type Theme = "light" | "dark";

export function ThemeProvider({ serverTheme }: { serverTheme?: Theme | null }) {
  useEffect(() => {
    // Priority: serverTheme (DB) > localStorage > system preference
    let theme: Theme;

    if (serverTheme) {
      // User is authenticated and has a theme preference in DB
      theme = serverTheme;
      // Sync to localStorage for consistency
      localStorage.setItem("theme", theme);
    } else {
      // User is not authenticated or no DB preference - use localStorage or system
      const savedTheme = localStorage.getItem("theme") as Theme | null;
      const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
      theme = savedTheme || (prefersDark ? "dark" : "light");
    }

    document.documentElement.classList.toggle("dark", theme === "dark");
  }, [serverTheme]);

  return null;
}
