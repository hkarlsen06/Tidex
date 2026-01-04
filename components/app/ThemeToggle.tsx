"use client";

import { useSyncExternalStore } from "react";
import { useTheme } from "./ThemeProvider";
import { useTranslations } from "@/lib/i18n/client";
import { isNativePlatform } from "@/lib/capacitor/platform";

// Subscribe is a no-op since platform detection doesn't change
const subscribe = () => () => {};

// Server always returns false; client checks platform
const getSnapshot = () => isNativePlatform();
const getServerSnapshot = () => false;

export function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();
  const { t } = useTranslations();
  const isNative = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);

  // Hide theme toggle on native platforms - theme follows device settings
  if (isNative) {
    return null;
  }

  return (
    <button
      type="button"
      onClick={toggleTheme}
      className="flex w-full items-center gap-3 px-4 py-2 text-sm text-text-primary hover:bg-accent"
      role="menuitem"
    >
      {theme === "dark" ? (
        <>
          <svg
            className="h-4 w-4"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <circle cx="12" cy="12" r="4" />
            <path d="M12 2v2" />
            <path d="M12 20v2" />
            <path d="m4.93 4.93 1.41 1.41" />
            <path d="m17.66 17.66 1.41 1.41" />
            <path d="M2 12h2" />
            <path d="M20 12h2" />
            <path d="m6.34 17.66-1.41 1.41" />
            <path d="m19.07 4.93-1.41 1.41" />
          </svg>
          {t.userMenu.lightMode}
        </>
      ) : (
        <>
          <svg
            className="h-4 w-4"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z" />
          </svg>
          {t.userMenu.darkMode}
        </>
      )}
    </button>
  );
}
