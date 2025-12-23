"use client";

import { useCallback, useEffect, useState } from "react";

const STORAGE_KEY = "sharing-view-state";

type SharingViewState = {
  sharerId: string | null;
};

/**
 * Hook for persisting the sharing view state across navigation.
 * Saves the currently viewed sharer ID to localStorage so that
 * navigating back to /sharing restores the previous view.
 */
export function useSharingViewState() {
  const [state, setState] = useState<SharingViewState>({ sharerId: null });
  const [isLoaded, setIsLoaded] = useState(false);

  // Load state from localStorage on mount
  useEffect(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as SharingViewState;
        setState(parsed);
      }
    } catch {
      // Ignore parse errors
    }
    setIsLoaded(true);
  }, []);

  // Save the current sharer ID to localStorage
  const saveViewState = useCallback((sharerId: string | null) => {
    const newState: SharingViewState = { sharerId };
    setState(newState);
    try {
      if (sharerId) {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(newState));
      } else {
        // Clear the saved state when navigating back to main view
        localStorage.removeItem(STORAGE_KEY);
      }
    } catch {
      // Ignore storage errors
    }
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
    savedSharerId: state.sharerId,
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
