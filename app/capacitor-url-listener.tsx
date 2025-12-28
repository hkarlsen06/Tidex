"use client";

import { useEffect, useRef } from "react";
import { Capacitor } from "@capacitor/core";

// Module-level flag to prevent double-registration across HMR and re-renders
let listenerRegistered = false;

/**
 * Global Capacitor URL listener for handling deep links.
 *
 * This component MUST be mounted at the root layout level so it's present
 * on ALL routes, including unauthenticated pages like /login and /signup.
 *
 * When OAuth completes on iOS, the provider redirects to tidex://auth/callback.
 * This listener:
 * 1. Receives the deep link via Capacitor's appUrlOpen event
 * 2. Closes the in-app browser overlay
 * 3. Forwards query params to the HTTPS callback URL
 *
 * ChunkLoadError resilience:
 * - If dynamic imports fail due to stale chunks after a deploy, retries once after 1s
 * - Uses module-level flag to prevent double-registration
 */
export function CapacitorUrlListener() {
  const hasRetried = useRef(false);

  useEffect(() => {
    // Only run on native platforms (iOS/Android)
    if (!Capacitor.isNativePlatform()) return;

    // Prevent double-registration
    if (listenerRegistered) return;

    let cleanup: (() => void) | undefined;
    let retryTimeout: ReturnType<typeof setTimeout> | undefined;

    const setupListener = async (isRetry = false) => {
      try {
        // Dynamic import to avoid loading Capacitor plugins on web
        const { App } = await import("@capacitor/app");
        const { Browser } = await import("@capacitor/browser");

        // Mark as registered before adding listener
        listenerRegistered = true;

        const listenerHandle = await App.addListener("appUrlOpen", async ({ url }) => {
          // Check if this is our OAuth callback scheme
          if (url.startsWith("tidex://auth/callback")) {
            // Close the in-app browser overlay immediately
            try {
              await Browser.close();
            } catch {
              // Browser may already be closed, silently ignore
            }

            // Parse the custom scheme URL
            const customUrl = new URL(url);

            // Build the HTTPS callback URL preserving all query params
            const httpsCallbackUrl = new URL("https://app.tidex.no/auth/callback");
            customUrl.searchParams.forEach((value, key) => {
              httpsCallbackUrl.searchParams.set(key, value);
            });

            // Small delay to ensure browser is fully closed before navigation
            setTimeout(() => {
              window.location.href = httpsCallbackUrl.toString();
            }, 100);
          }
        });

        cleanup = () => {
          listenerHandle.remove();
          listenerRegistered = false;
        };
      } catch (error) {
        const isChunkError =
          error instanceof Error &&
          (error.name === "ChunkLoadError" ||
            error.message.includes("Loading chunk") ||
            error.message.includes("ChunkLoadError"));

        if (isChunkError && !isRetry && !hasRetried.current) {
          // ChunkLoadError: retry once after 1 second
          console.warn("[CAPACITOR] ChunkLoadError on setup, retrying in 1s");
          hasRetried.current = true;
          retryTimeout = setTimeout(() => setupListener(true), 1000);
        } else if (isChunkError) {
          // Already retried, give up silently
          console.warn("[CAPACITOR] ChunkLoadError persists after retry");
        } else {
          // Non-chunk error, log once
          console.warn("[CAPACITOR] Failed to setup URL listener");
        }
      }
    };

    setupListener();

    return () => {
      if (retryTimeout) clearTimeout(retryTimeout);
      cleanup?.();
    };
  }, []);

  return null;
}
