import { isNativePlatform } from "./platform";

/**
 * Haptic feedback utilities for native iOS/Android
 * Gracefully no-ops on web platforms
 */

export type HapticImpactStyle = "light" | "medium" | "heavy";
export type HapticNotificationType = "success" | "warning" | "error";

/**
 * Trigger impact haptic feedback
 * Use for UI interactions like button taps, toggles, selections
 */
export async function impactHaptic(
  style: HapticImpactStyle = "medium"
): Promise<void> {
  if (!isNativePlatform()) return;

  try {
    const { Haptics, ImpactStyle } = await import("@capacitor/haptics");

    const styleMap = {
      light: ImpactStyle.Light,
      medium: ImpactStyle.Medium,
      heavy: ImpactStyle.Heavy,
    };

    await Haptics.impact({ style: styleMap[style] });
  } catch {
    // Silently fail - haptics are optional enhancement
  }
}

/**
 * Trigger notification haptic feedback
 * Use for success, warning, or error states
 */
export async function notificationHaptic(
  type: HapticNotificationType = "success"
): Promise<void> {
  if (!isNativePlatform()) return;

  try {
    const { Haptics, NotificationType } = await import("@capacitor/haptics");

    const typeMap = {
      success: NotificationType.Success,
      warning: NotificationType.Warning,
      error: NotificationType.Error,
    };

    await Haptics.notification({ type: typeMap[type] });
  } catch {
    // Silently fail - haptics are optional enhancement
  }
}

/**
 * Trigger selection change haptic
 * Use for scrolling through lists, date pickers, etc.
 */
export async function selectionHaptic(): Promise<void> {
  if (!isNativePlatform()) return;

  try {
    const { Haptics } = await import("@capacitor/haptics");
    await Haptics.selectionChanged();
  } catch {
    // Silently fail - haptics are optional enhancement
  }
}

/**
 * Start a selection session for repeated selectionChanged haptics.
 * Some platforms require this before selectionChanged will fire reliably.
 */
export async function selectionStartHaptic(): Promise<void> {
  if (!isNativePlatform()) return;

  try {
    const { Haptics } = await import("@capacitor/haptics");
    await Haptics.selectionStart();
  } catch {
    // Silently fail - haptics are optional enhancement
  }
}

/**
 * End a selection session after repeated selectionChanged haptics.
 */
export async function selectionEndHaptic(): Promise<void> {
  if (!isNativePlatform()) return;

  try {
    const { Haptics } = await import("@capacitor/haptics");
    await Haptics.selectionEnd();
  } catch {
    // Silently fail - haptics are optional enhancement
  }
}

/**
 * Trigger a celebration haptic pattern
 * Use for achievements, completions, celebrations
 */
export async function celebrationHaptic(): Promise<void> {
  if (!isNativePlatform()) return;

  try {
    const { Haptics, NotificationType } = await import("@capacitor/haptics");

    // Success haptic followed by a light impact for extra "pop"
    await Haptics.notification({ type: NotificationType.Success });
  } catch {
    // Silently fail - haptics are optional enhancement
  }
}
