"use client";

import { createContext, useContext, useSyncExternalStore, type ReactNode } from "react";
import { isIOSPlatform } from "@/lib/capacitor/platform";

const NativeTabBarContext = createContext<boolean>(false);

// Check if native iOS - uses multiple detection methods:
// 1. Capacitor bridge (if available)
// 2. CSS class added by inline script (fallback when bridge not ready)
function checkIsNativeIOS(): boolean {
  if (typeof window === "undefined") return false;

  // Check Capacitor bridge first (most reliable when available)
  if (isIOSPlatform()) return true;

  // Fallback: check for native-ios class added by inline script in layout.tsx
  // This handles the case where Capacitor bridge isn't ready yet
  return document.documentElement.classList.contains("native-ios");
}

// Stable references for useSyncExternalStore
const subscribe = () => () => {};  // Platform never changes at runtime
const getSnapshot = () => checkIsNativeIOS();
const getServerSnapshot = () => false;  // SSR always returns false

export function NativeTabBarProvider({ children }: { children: ReactNode }) {
  // useSyncExternalStore handles SSR hydration correctly without triggering
  // cascading renders from setState in useEffect
  const hasNativeTabBar = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);

  return (
    <NativeTabBarContext.Provider value={hasNativeTabBar}>
      {children}
    </NativeTabBarContext.Provider>
  );
}

export function useHasNativeTabBar(): boolean {
  return useContext(NativeTabBarContext);
}
