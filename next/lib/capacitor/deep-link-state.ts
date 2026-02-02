/**
 * Deep Link State Manager
 *
 * Coordinates splash screen hiding with deep link navigation to prevent
 * showing the default route before navigating to the deep link target.
 *
 * Flow:
 * 1. On app launch, check for pending deep link via App.getLaunchUrl()
 * 2. If deep link exists, set pendingDeepLink = true
 * 3. Splash hiding components check this flag and wait if pending
 * 4. After navigation completes, call markDeepLinkHandled()
 * 5. Splash is then allowed to hide
 *
 * Edge cases handled:
 * - Cold start with deep link: getLaunchUrl() returns the URL
 * - Warm start (app in background): appUrlOpen event fires, but splash is already hidden
 * - No deep link: initialization resolves immediately, splash hides normally
 * - OAuth callbacks: handled separately (redirect to /auth/callback)
 * - Timeout fallback: if navigation takes >3s, allow splash to hide anyway
 */

import { Capacitor } from "@capacitor/core";

// State flags
let initialized = false;
let pendingDeepLink = false;
let pendingDeepLinkUrl: string | null = null;
let initPromise: Promise<void> | null = null;

// Subscribers waiting for deep link resolution
const subscribers: Array<() => void> = [];

// Timeout to prevent stuck splash if something goes wrong
const DEEP_LINK_TIMEOUT_MS = 3000;
let timeoutId: ReturnType<typeof setTimeout> | null = null;

/**
 * Check if a URL should block splash (navigation-triggering deep links).
 * OAuth callbacks don't block because they do a full page redirect.
 */
function shouldBlockSplash(url: string): boolean {
  // OAuth callbacks redirect via window.location.href, don't need to block
  if (url.startsWith("tidex://auth/callback")) {
    return false;
  }
  // Widget/notification deep links need to wait for router.push()
  if (url.startsWith("tidex://shifts")) {
    return true;
  }
  // Unknown deep links - don't block to be safe
  return false;
}

/**
 * Initialize deep link state by checking for launch URL.
 * Called once on app startup. Returns a promise that resolves when
 * we know whether there's a pending deep link.
 */
export async function initDeepLinkState(): Promise<void> {
  // Return existing promise if already initializing
  if (initPromise) {
    return initPromise;
  }

  // Already initialized
  if (initialized) {
    return Promise.resolve();
  }

  initPromise = (async () => {
    // Only check on native platforms
    if (!Capacitor.isNativePlatform()) {
      initialized = true;
      return;
    }

    try {
      const { App } = await import("@capacitor/app");
      const result = await App.getLaunchUrl();

      if (result?.url && shouldBlockSplash(result.url)) {
        pendingDeepLink = true;
        pendingDeepLinkUrl = result.url;

        // Safety timeout - don't keep splash forever if navigation fails
        timeoutId = setTimeout(() => {
          console.warn(
            "[DeepLinkState] Timeout waiting for deep link navigation, allowing splash"
          );
          markDeepLinkHandled();
        }, DEEP_LINK_TIMEOUT_MS);
      }
    } catch (error) {
      // getLaunchUrl can fail on some platforms, just proceed normally
      console.warn("[DeepLinkState] Failed to get launch URL:", error);
    }

    initialized = true;
  })();

  return initPromise;
}

/**
 * Check if there's a pending deep link that should delay splash hiding.
 * Returns true if we should wait, false if splash can hide.
 */
export function hasPendingDeepLink(): boolean {
  return pendingDeepLink;
}

/**
 * Get the pending deep link URL if any.
 */
export function getPendingDeepLinkUrl(): string | null {
  return pendingDeepLinkUrl;
}

/**
 * Mark deep link as handled (navigation complete).
 * This allows splash to hide and notifies any waiting subscribers.
 */
export function markDeepLinkHandled(): void {
  if (!pendingDeepLink) return;

  pendingDeepLink = false;
  pendingDeepLinkUrl = null;

  // Clear timeout
  if (timeoutId) {
    clearTimeout(timeoutId);
    timeoutId = null;
  }

  // Notify all subscribers
  subscribers.forEach((callback) => callback());
  subscribers.length = 0;
}

/**
 * Wait for deep link to be handled (or no deep link pending).
 * Use this in splash-hiding logic to wait for navigation.
 */
export function waitForDeepLinkHandled(): Promise<void> {
  // If no pending deep link, resolve immediately
  if (!pendingDeepLink) {
    return Promise.resolve();
  }

  // Otherwise wait for markDeepLinkHandled() to be called
  return new Promise((resolve) => {
    subscribers.push(resolve);
  });
}

/**
 * Check if initialization is complete.
 */
export function isInitialized(): boolean {
  return initialized;
}

/**
 * Reset state (for testing purposes).
 */
export function resetDeepLinkState(): void {
  initialized = false;
  pendingDeepLink = false;
  pendingDeepLinkUrl = null;
  initPromise = null;
  subscribers.length = 0;
  if (timeoutId) {
    clearTimeout(timeoutId);
    timeoutId = null;
  }
}
