import { registerPlugin } from "@capacitor/core";

// Define the NativeSplash plugin interface
export interface NativeSplashPlugin {
  hide(options?: { fadeOutDuration?: number }): Promise<void>;
  show(): Promise<void>;
  isVisible(): Promise<{ visible: boolean }>;
}

// Register the custom native plugin
export const NativeSplash = registerPlugin<NativeSplashPlugin>("NativeSplash");

// Module-level flag to ensure we only hide once
let splashHidden = false;

/**
 * Hide the native splash screen with a fade animation.
 * Safe to call multiple times - only hides once.
 *
 * @param fadeOutDuration - Duration of fade animation in milliseconds (default: 200)
 */
export async function hideSplash(fadeOutDuration = 200): Promise<void> {
  if (splashHidden) return;

  splashHidden = true;

  try {
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
