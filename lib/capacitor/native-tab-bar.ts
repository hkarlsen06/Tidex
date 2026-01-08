import { registerPlugin } from "@capacitor/core";
import type { PluginListenerHandle } from "@capacitor/core";

export interface TabSelectedEvent {
  index: number;
  route: string;
}

export interface NativeTabBarPlugin {
  setSelectedTab(options: { index: number }): Promise<void>;
  clearSelection(): Promise<void>;
  setTabBadge(options: { index: number; value?: string }): Promise<void>;
  hide(): Promise<void>;
  show(): Promise<void>;
  isAvailable(): Promise<{ available: boolean }>;
  getTabBarHeight(): Promise<{ height: number }>;
  addListener(
    eventName: "tabSelected",
    listenerFunc: (event: TabSelectedEvent) => void
  ): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}

// Tab definitions (must match Swift tabs array)
// Index order is the contract between native and web
// Prefixed with _ as it serves as documentation; actual matching uses optimized conditionals below
const _TAB_DEFINITIONS = [
  { route: "/", prefix: null },            // Home - exact match only
  { route: "/shifts", prefix: "/shifts" }, // Shifts section
  { route: "/shifts/add", prefix: "/shifts/add" }, // Add (more specific, checked first)
  { route: "/stats", prefix: "/stats" },   // Stats section
  { route: "/sharing", prefix: "/sharing" }, // Sharing section
] as const;

// Known locales - extend this list if more locales are added
const KNOWN_LOCALES = ["no", "en"];

/**
 * Get tab index from pathname using longest-prefix matching.
 * Handles locale prefixes, query strings, and nested routes.
 */
export function getTabIndexFromPath(pathname: string): number | null {
  // Strip locale prefix if first segment matches a known locale
  // This is driven by KNOWN_LOCALES to easily extend for new locales
  const localePattern = new RegExp(`^\\/(${KNOWN_LOCALES.join("|")})(?=\\/|$)`);
  let path = pathname
    .replace(localePattern, "")
    .split("?")[0]
    .split("#")[0];

  // Ensure path starts with /
  if (!path || path === "") path = "/";
  if (!path.startsWith("/")) path = "/" + path;

  // Longest-prefix matching (check more specific routes first)
  // Order: /shifts/add (index 2), then /shifts (index 1), etc.

  // Check /shifts/add first (most specific in /shifts section)
  if (path === "/shifts/add" || path.startsWith("/shifts/add/")) {
    return 2;
  }

  // Check /sharing
  if (path === "/sharing" || path.startsWith("/sharing/")) {
    return 4;
  }

  // Check /stats
  if (path === "/stats" || path.startsWith("/stats/")) {
    return 3;
  }

  // Check /shifts (after /shifts/add to avoid false match)
  if (path === "/shifts" || path.startsWith("/shifts/")) {
    return 1;
  }

  // Check home (exact match)
  if (path === "/") {
    return 0;
  }

  // No matching tab (e.g., /settings, /onboarding)
  return null;
}

// Register plugin with web stub
export const NativeTabBar = registerPlugin<NativeTabBarPlugin>("NativeTabBar", {
  web: () => import("./native-tab-bar-web").then((m) => new m.NativeTabBarWeb()),
});
