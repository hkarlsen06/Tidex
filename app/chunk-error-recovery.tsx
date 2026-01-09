"use client";

import { useEffect } from "react";
import { isNativePlatform } from "@/lib/capacitor/platform";

const RELOAD_FLAG = "chunk_reload_attempted";

/**
 * Check if we're in tunnel mode (local-ios development through Cloudflare tunnel)
 * This disables chunk error recovery to prevent infinite reload loops
 */
function checkTunnelMode(): boolean {
  // Check env variable first
  if (process.env.NEXT_PUBLIC_TUNNEL_MODE === "true") {
    return true;
  }
  // Fallback: check hostname (dev tunnel URL)
  if (typeof window !== "undefined" && window.location.hostname === "dev.tidex.no") {
    return true;
  }
  return false;
}

/**
 * Global handler for Next.js ChunkLoadError recovery.
 *
 * When a deployment happens, cached JS chunks may become stale.
 * This component catches chunk load failures and forces a hard reload
 * to fetch fresh chunks from the server.
 *
 * Safety:
 * - Only triggers on known chunk load error patterns
 * - Uses sessionStorage flag to prevent reload loops (max 1 reload per session)
 * - Clears flag on successful page load so future sessions can retry
 * - Disabled entirely in tunnel mode (local-ios) to prevent HMR-related loops
 *
 * Capacitor/Native:
 * - On native platforms, we delay the reload slightly to avoid cancelling
 *   in-progress navigations, which would trigger the offline.html page
 * - Uses a 500ms delay to let the current navigation settle first
 */
export function ChunkErrorRecovery() {
  useEffect(() => {
    // In tunnel mode, don't set up chunk error recovery at all
    // HMR failures through the tunnel would cause infinite reload loops
    if (checkTunnelMode()) {
      console.log("[CHUNK] Tunnel mode detected, chunk error recovery disabled");
      return;
    }
    // Clear the reload flag on successful mount
    // This means the page loaded successfully, so future chunk errors can trigger a reload
    try {
      sessionStorage.removeItem(RELOAD_FLAG);
    } catch {
      // sessionStorage may not be available (e.g., private browsing restrictions)
    }

    // Helper to perform reload with native platform awareness
    const performReload = () => {
      // On native platforms (Capacitor), delay the reload to avoid cancelling
      // in-progress navigations. This prevents the WebView from showing
      // offline.html due to NSURLErrorCancelled (-999).
      if (isNativePlatform()) {
        console.warn("[CHUNK] Native platform detected, delaying reload");
        setTimeout(() => {
          window.location.reload();
        }, 500);
      } else {
        window.location.reload();
      }
    };

    const handleError = (event: ErrorEvent) => {
      const error = event.error;
      if (!error) return;

      const isChunkError =
        error.name === "ChunkLoadError" ||
        (error.message &&
          (error.message.includes("Loading chunk") ||
            error.message.includes("ChunkLoadError") ||
            error.message.includes("Failed to fetch dynamically imported module")));

      if (!isChunkError) return;

      // Check if we've already attempted a reload this session
      try {
        if (sessionStorage.getItem(RELOAD_FLAG)) {
          // Already tried, don't loop
          console.warn("[CHUNK] ChunkLoadError persists after reload, not retrying");
          return;
        }

        // Set flag before reloading
        sessionStorage.setItem(RELOAD_FLAG, "1");
        console.warn("[CHUNK] ChunkLoadError detected, reloading page");

        // Force hard reload to bypass cache
        performReload();
      } catch {
        // sessionStorage not available, skip reload to avoid potential loop
      }
    };

    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
      const error = event.reason;
      if (!error) return;

      const errorMessage = error.message || String(error);
      const errorName = error.name || "";

      const isChunkError =
        errorName === "ChunkLoadError" ||
        errorMessage.includes("Loading chunk") ||
        errorMessage.includes("ChunkLoadError") ||
        errorMessage.includes("Failed to fetch dynamically imported module");

      if (!isChunkError) return;

      // Check if we've already attempted a reload this session
      try {
        if (sessionStorage.getItem(RELOAD_FLAG)) {
          console.warn("[CHUNK] ChunkLoadError persists after reload, not retrying");
          return;
        }

        sessionStorage.setItem(RELOAD_FLAG, "1");
        console.warn("[CHUNK] ChunkLoadError detected in promise, reloading page");

        performReload();
      } catch {
        // sessionStorage not available
      }
    };

    window.addEventListener("error", handleError);
    window.addEventListener("unhandledrejection", handleUnhandledRejection);

    return () => {
      window.removeEventListener("error", handleError);
      window.removeEventListener("unhandledrejection", handleUnhandledRejection);
    };
  }, []);

  return null;
}
