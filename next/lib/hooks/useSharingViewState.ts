"use client";

import { useCallback, useSyncExternalStore } from "react";

const STORAGE_KEY = "sharing-view-state";

type SharingViewState = {
  sharerId: string | null;
};

const listeners = new Set<() => void>();

const emit = () => {
  for (const listener of listeners) {
    listener();
  }
};

const subscribe = (listener: () => void) => {
  listeners.add(listener);

  const onStorage = (event: StorageEvent) => {
    if (event.key === STORAGE_KEY) {
      listener();
    }
  };

  if (typeof window !== "undefined") {
    window.addEventListener("storage", onStorage);
  }

  return () => {
    listeners.delete(listener);
    if (typeof window !== "undefined") {
      window.removeEventListener("storage", onStorage);
    }
  };
};

const getSavedSharerSnapshot = (): string | null => {
  if (typeof window === "undefined") return null;
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored) as SharingViewState;
      return parsed.sharerId ?? null;
    }
  } catch {
    // Ignore parse errors
  }
  return null;
};

const getServerSharerSnapshot = () => null;

const getLoadedSnapshot = () => typeof window !== "undefined";
const getServerLoadedSnapshot = () => false;

/**
 * Hook for persisting the sharing view state across navigation.
 * Saves the currently viewed sharer ID to localStorage so that
 * navigating back to /sharing restores the previous view.
 */
export function useSharingViewState() {
  const savedSharerId = useSyncExternalStore(
    subscribe,
    getSavedSharerSnapshot,
    getServerSharerSnapshot,
  );
  const isLoaded = useSyncExternalStore(
    () => () => {},
    getLoadedSnapshot,
    getServerLoadedSnapshot,
  );

  // Save the current sharer ID to localStorage
  const saveViewState = useCallback((sharerId: string | null) => {
    try {
      if (sharerId) {
        const newState: SharingViewState = { sharerId };
        localStorage.setItem(STORAGE_KEY, JSON.stringify(newState));
      } else {
        // Clear the saved state when navigating back to main view
        localStorage.removeItem(STORAGE_KEY);
      }
    } catch {
      // Ignore storage errors
    }
    emit();
  }, []);

  // Get the saved sharer ID
  const getSavedSharerId = useCallback((): string | null => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as SharingViewState;
        return parsed.sharerId;
      }
    } catch {
      // Ignore parse errors
    }
    return null;
  }, []);

  return {
    savedSharerId,
    isLoaded,
    saveViewState,
    getSavedSharerId,
  };
}

/**
 * Get the sharing URL with saved view state (for use in navigation).
 * This is a static function that can be called without the hook.
 */
export function getSharingUrlWithState(locale: string): string {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored) as SharingViewState;
      if (parsed.sharerId) {
        return `/${locale}/sharing?view=${parsed.sharerId}`;
      }
    }
  } catch {
    // Ignore parse errors
  }
  return `/${locale}/sharing`;
}

/**
 * Clear the saved sharing view state.
 * Use this when navigating back to the main sharing list.
 */
export function clearSharingViewState(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Ignore storage errors
  }
  emit();
}
