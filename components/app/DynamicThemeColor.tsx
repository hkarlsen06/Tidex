"use client";

import { useEffect } from "react";

/**
 * Component that dynamically updates the browser's theme-color meta tag
 * based on the current theme (light/dark mode).
 *
 * Light mode: #f1f4f8 (matches --surface-primary: hsl(220 35% 96%))
 * Dark mode: #0e172a (matches dark mode --surface-primary: hsl(220 49% 11%))
 */
export function DynamicThemeColor() {
  useEffect(() => {
    const updateThemeColor = () => {
      const isDark = document.documentElement.classList.contains("dark");
      const themeColor = isDark ? "#0e172a" : "#f1f4f8";

      // Update or create theme-color meta tag
      let metaThemeColor = document.querySelector('meta[name="theme-color"]');
      if (!metaThemeColor) {
        metaThemeColor = document.createElement("meta");
        metaThemeColor.setAttribute("name", "theme-color");
        document.head.appendChild(metaThemeColor);
      }
      metaThemeColor.setAttribute("content", themeColor);
    };

    // Update immediately
    updateThemeColor();

    // Watch for theme changes via MutationObserver
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (
          mutation.type === "attributes" &&
          mutation.attributeName === "class"
        ) {
          updateThemeColor();
        }
      });
    });

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"],
    });

    return () => observer.disconnect();
  }, []);

  return null;
}
