"use client";

import { useEffect } from "react";
import { Capacitor } from "@capacitor/core";

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
 */
export function CapacitorUrlListener() {
  useEffect(() => {
    // Only run on native platforms (iOS/Android)
    if (!Capacitor.isNativePlatform()) return;

    let cleanup: (() => void) | undefined;

    const setupListener = async () => {
      try {
        // Dynamic import to avoid loading Capacitor plugins on web
        const { App } = await import("@capacitor/app");
        const { Browser } = await import("@capacitor/browser");

        const listenerHandle = await App.addListener("appUrlOpen", async ({ url }) => {
          // TODO: Remove this log after verifying the handler fires correctly
          console.log("[CAPACITOR] appUrlOpen received:", url);

          // Check if this is our OAuth callback scheme
          if (url.startsWith("tidex://auth/callback")) {
            // Close the in-app browser overlay immediately
            try {
              await Browser.close();
              console.log("[CAPACITOR] Browser closed");
            } catch (e) {
              // Browser may already be closed, ignore
              console.log("[CAPACITOR] Browser.close() failed (may already be closed):", e);
            }

            // Parse the custom scheme URL
            const customUrl = new URL(url);

            // Build the HTTPS callback URL preserving all query params
            const httpsCallbackUrl = new URL("https://app.tidex.no/auth/callback");
            customUrl.searchParams.forEach((value, key) => {
              httpsCallbackUrl.searchParams.set(key, value);
            });

            console.log("[CAPACITOR] Redirecting to HTTPS callback:", httpsCallbackUrl.toString());

            // Small delay to ensure browser is fully closed before navigation
            setTimeout(() => {
              window.location.href = httpsCallbackUrl.toString();
            }, 100);
          }
        });

        cleanup = () => {
          listenerHandle.remove();
        };
      } catch (error) {
        console.warn("[CAPACITOR] Failed to setup appUrlOpen listener:", error);
      }
    };

    setupListener();

    return () => {
      cleanup?.();
    };
  }, []);

  return null;
}
