import { Capacitor } from "@capacitor/core";

/**
 * Check if running in a native Capacitor environment (iOS/Android)
 * Returns false on web to avoid loading Capacitor plugins
 *
 * Note: When using remote URLs, we also check for the native bridge
 * being available via window.Capacitor which is injected by the native shell.
 */
export function isNativePlatform(): boolean {
  if (typeof window === "undefined") return false;

  // Check both the Capacitor API and the native bridge
  // The bridge is injected by the native shell even when loading remote content
  const hasNativeBridge = !!(window as any).Capacitor?.isNativePlatform;

  if (hasNativeBridge) {
    return Capacitor.isNativePlatform();
  }

  // Fallback: check if we're in a WebView by looking for platform hints
  // iOS WKWebView has specific characteristics
  const userAgent = navigator.userAgent || '';
  const isIOSWebView = /iPhone|iPad|iPod/.test(userAgent) && !(window as any).MSStream && !/Safari/.test(userAgent);

  return isIOSWebView;
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
 */
export function getPlatform(): "ios" | "android" | "web" {
  if (typeof window === "undefined") return "web";

  // Check if Capacitor bridge is available
  const hasNativeBridge = !!(window as any).Capacitor?.getPlatform;

  if (hasNativeBridge) {
    return Capacitor.getPlatform() as "ios" | "android" | "web";
  }

  // Fallback: detect platform from user agent
  const userAgent = navigator.userAgent || '';

  // Check for iOS WebView (WKWebView doesn't have Safari in UA when embedded)
  if (/iPhone|iPad|iPod/.test(userAgent) && !(window as any).MSStream) {
    // If we're in an iOS WebView (no Safari in UA), treat as native iOS
    if (!/Safari/.test(userAgent) || (window as any).webkit?.messageHandlers) {
      return "ios";
    }
  }

  // Check for Android WebView
  if (/Android/.test(userAgent) && /wv/.test(userAgent)) {
    return "android";
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
