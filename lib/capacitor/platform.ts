import { Capacitor } from "@capacitor/core";

/**
 * Check if running in a native Capacitor environment (iOS/Android)
 * Returns false on web to avoid loading Capacitor plugins
 */
export function isNativePlatform(): boolean {
  if (typeof window === "undefined") return false;
  return Capacitor.isNativePlatform();
}

/**
 * Get the current platform name
 * Returns 'ios', 'android', or 'web'
 */
export function getPlatform(): "ios" | "android" | "web" {
  if (typeof window === "undefined") return "web";
  return Capacitor.getPlatform() as "ios" | "android" | "web";
}
