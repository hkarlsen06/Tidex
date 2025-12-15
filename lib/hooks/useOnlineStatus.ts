"use client";

import { useState, useEffect } from "react";

/**
 * Hook to track online/offline status
 * Returns true when offline, false when online
 *
 * Note: Always returns false during SSR and initial hydration to prevent
 * hydration mismatches. The actual offline status is synced after mount.
 *
 * @returns {boolean} isOffline - true when the browser is offline
 */
export function useOnlineStatus(): boolean {
  // Always start with false (online) to match server render and prevent hydration mismatch
  const [isOffline, setIsOffline] = useState(false);

  useEffect(() => {
    // Sync with actual status after mount
    setIsOffline(!navigator.onLine);

    const handleOnline = () => setIsOffline(false);
    const handleOffline = () => setIsOffline(true);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  return isOffline;
}
