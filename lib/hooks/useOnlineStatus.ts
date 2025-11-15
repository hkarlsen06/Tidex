"use client";

import { useState, useEffect } from "react";

/**
 * Hook to track online/offline status
 * Returns true when offline, false when online
 *
 * @returns {boolean} isOffline - true when the browser is offline
 */
export function useOnlineStatus(): boolean {
  // Initialize state from navigator.onLine (avoids setState in effect)
  const [isOffline, setIsOffline] = useState(() => {
    if (typeof navigator === 'undefined') return false;
    return !navigator.onLine;
  });

  useEffect(() => {

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
