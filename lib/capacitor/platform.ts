import { Capacitor } from "@capacitor/core";

/**
 * Check if running in a native Capacitor environment (iOS/Android)
 * Returns false on web to avoid loading Capacitor plugins
 *
 * Note: Only returns true if the actual Capacitor native bridge is present.
 * We do NOT use user agent fallbacks because they incorrectly detect
 * Chrome iOS and other in-app browsers as "native".
 */
export function isNativePlatform(): boolean {
  if (typeof window === "undefined") return false;

  // Only return true if we have the actual Capacitor native bridge
  const hasNativeBridge = !!(window as any).Capacitor?.isNativePlatform;

  if (hasNativeBridge) {
    return Capacitor.isNativePlatform();
  }

  return false;
}

/**
 * Check if running on native iOS (inside Capacitor app)
 * Returns false for iOS Safari/web - only true when in the native iOS app
 */
export function isIOSPlatform(): boolean {
  if (typeof window === "undefined") return false;

  // Only return true if we have the Capacitor native bridge AND it reports iOS
  const hasNativeBridge = !!(window as any).Capacitor?.getPlatform;
  if (!hasNativeBridge) return false;

  return (window as any).Capacitor.getPlatform() === "ios";
}

/**
 * Get the current platform name
 * Returns 'ios', 'android', or 'web'
 *
 * Note: Only returns 'ios' or 'android' if the actual Capacitor native bridge
 * is present. We do NOT use user agent fallbacks because they incorrectly
 * detect Chrome iOS and other in-app browsers as native platforms.
 */
export function getPlatform(): "ios" | "android" | "web" {
  if (typeof window === "undefined") return "web";

  // Only return native platform if we have the actual Capacitor native bridge
  const hasNativeBridge = !!(window as any).Capacitor?.getPlatform;

  if (hasNativeBridge) {
    return Capacitor.getPlatform() as "ios" | "android" | "web";
  }

  return "web";
}

/**
 * Wait for Capacitor bridge to be available (for use with remote URLs)
 * Returns a promise that resolves when the bridge is ready or times out
 */
export function waitForCapacitorBridge(timeoutMs: number = 2000): Promise<boolean> {
  return new Promise((resolve) => {
    // If already available, resolve immediately
    if ((window as any).Capacitor?.isNativePlatform) {
      resolve(true);
      return;
    }

    const startTime = Date.now();

    const checkBridge = () => {
      if ((window as any).Capacitor?.isNativePlatform) {
        resolve(true);
        return;
      }

      if (Date.now() - startTime > timeoutMs) {
        resolve(false);
        return;
      }

      requestAnimationFrame(checkBridge);
    };

    requestAnimationFrame(checkBridge);
  });
}
