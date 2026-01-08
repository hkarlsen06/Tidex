"use client";

import { createContext, useContext, useSyncExternalStore, type ReactNode } from "react";
import { isNativeIOSWithFallback } from "@/lib/capacitor/platform";

const NativeTabBarContext = createContext<boolean>(false);

// Stable references for useSyncExternalStore
const subscribe = () => () => {};  // Platform never changes at runtime
const getSnapshot = () => isNativeIOSWithFallback();
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
