"use client";

import { useNativeTabBar } from "@/lib/hooks/useNativeTabBar";

export function NativeTabBarSync() {
  useNativeTabBar();
  return null;
}
