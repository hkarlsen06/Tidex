"use client";

import { useEffect } from "react";

/**
 * Component that dynamically updates the browser's theme-color meta tag
 * based on the current theme (light/dark mode).
 *
 * Light mode: #3b82f6 (matches --brand-gradientMid)
 * Dark mode: #6495ed (matches dark mode --brand-gradientMid)
 */
export function DynamicThemeColor() {
  useEffect(() => {
    const updateThemeColor = () => {
      const isDark = document.documentElement.classList.contains("dark");
      const themeColor = isDark ? "#6495ed" : "#3b82f6";

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
