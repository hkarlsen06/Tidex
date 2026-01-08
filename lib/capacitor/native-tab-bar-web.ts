import { WebPlugin } from "@capacitor/core";
import type { NativeTabBarPlugin } from "./native-tab-bar";

export class NativeTabBarWeb extends WebPlugin implements NativeTabBarPlugin {
  async setSelectedTab(_options: { index: number }): Promise<void> {
    // No-op on web
  }

  async setTabBadge(_options: { index: number; value?: string }): Promise<void> {
    // No-op on web
  }

  async setTabTitles(_options: { titles: string[] }): Promise<void> {
    // No-op on web (native tab bar only exists on iOS)
    // Note: Currently unused - tab titles are set from iOS device locale at launch.
    // Kept for potential future use (e.g., runtime language switching).
  }

  async hide(): Promise<void> {
    // No-op on web
  }

  async show(): Promise<void> {
    // No-op on web
  }

  async isAvailable(): Promise<{ available: boolean }> {
    return { available: false };
  }

  async clearSelection(): Promise<void> {
    // No-op on web
  }

  async getTabBarHeight(): Promise<{ height: number }> {
    return { height: 0 };
  }
}
