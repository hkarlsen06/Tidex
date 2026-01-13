import { registerPlugin } from "@capacitor/core";
import {
  initDeepLinkState,
  hasPendingDeepLink,
  waitForDeepLinkHandled,
} from "./deep-link-state";

// Define the NativeSplash plugin interface
export interface NativeSplashPlugin {
  hide(options?: { fadeOutDuration?: number }): Promise<void>;
  show(): Promise<void>;
  isVisible(): Promise<{ visible: boolean }>;
}

// Register the custom native plugin
export const NativeSplash = registerPlugin<NativeSplashPlugin>("NativeSplash");

/**
 * Module-level flag to ensure we only hide the splash once per session.
 *
 * Multiple components may call hideSplash():
 * - ShowNativeTabBar: Primary handler for authenticated routes (after tab bar shown)
 * - LoginClient/SignupPage: Primary handler for auth routes (on form ready)
 * - SplashScreenManager: Fallback safety net (3 second timeout)
 *
 * The first call wins, subsequent calls are no-ops.
 */
let splashHidden = false;

/**
 * Hide the native splash screen with a fade animation.
 *
 * Safe to call multiple times - only hides once per session. This idempotent
 * behavior allows multiple components to call hideSplash() without coordination,
 * ensuring the splash is hidden when ANY component is ready.
 *
 * If the app was opened via a deep link, this function waits for the deep link
 * navigation to complete before hiding the splash, preventing a flash of the
 * default route.
 *
 * @param fadeOutDuration - Duration of fade animation in milliseconds (default: 200)
 */
export async function hideSplash(fadeOutDuration = 200): Promise<void> {
  if (splashHidden) return;

  // Set flag BEFORE async calls to prevent race conditions where multiple
  // callers might pass the check before any completes
  splashHidden = true;

  try {
    // Initialize deep link state (checks for launch URL)
    await initDeepLinkState();

    // If there's a pending deep link, wait for navigation to complete
    if (hasPendingDeepLink()) {
      await waitForDeepLinkHandled();
    }

    await NativeSplash.hide({ fadeOutDuration });
  } catch {
    // Splash may already be hidden or plugin not available, ignore
  }
}

/**
 * Check if splash has already been hidden this session.
 */
export function isSplashHidden(): boolean {
  return splashHidden;
}

/**
 * Reset splash hidden state (for testing purposes).
 */
export function resetSplashState(): void {
  splashHidden = false;
}
