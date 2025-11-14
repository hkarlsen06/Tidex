'use client';

import { useEffect } from 'react';

/**
 * Service Worker registration component
 * Registers /sw.js and handles updates
 *
 * Features:
 * - Registers service worker on mount (production only)
 * - Detects when new service worker is available
 * - Automatically activates updates
 * - Logs registration lifecycle events
 */
export default function SWRegister() {
  useEffect(() => {
    // Only register in production and if service worker is supported
    if (
      typeof window === 'undefined' ||
      !('serviceWorker' in navigator) ||
      process.env.NODE_ENV !== 'production'
    ) {
      return;
    }

    let updateInterval: ReturnType<typeof setInterval> | null = null;
    let controllerChangeHandler: (() => void) | null = null;

    /**
     * Register service worker and set up update handling
     */
    async function registerServiceWorker() {
      try {
        const registration = await navigator.serviceWorker.register('/sw.js', {
          scope: '/',
        });

        console.log('[SW Registration] Success:', registration.scope);

        // Check for updates immediately
        registration.update();

        /**
         * Handle service worker update found
         * This fires when a new service worker is installing
         */
        const updateFoundHandler = () => {
          const newWorker = registration.installing;

          if (!newWorker) {
            return;
          }

          console.log('[SW Registration] Update found, new worker installing');

          /**
           * Monitor new service worker state changes
           */
          newWorker.addEventListener('statechange', () => {
            console.log('[SW Registration] New worker state:', newWorker.state);

            // When new worker is installed and waiting to activate
            if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
              console.log('[SW Registration] New version available, activating...');

              // Tell the new service worker to skip waiting and activate immediately
              newWorker.postMessage({ type: 'SKIP_WAITING' });

              // Optional: Show a notification to the user
              // You could dispatch a custom event here for a UI notification:
              // window.dispatchEvent(new CustomEvent('swUpdate'));
            }

            // When new worker has activated
            if (newWorker.state === 'activated') {
              console.log('[SW Registration] New version activated');

              // First time install - no reload needed
              if (!navigator.serviceWorker.controller) {
                return;
              }

              // Dispatch event instead of auto-reloading
              // This allows the app to decide when/how to reload
              // For example, could show a "New version available" banner
              console.log('[SW Registration] New version available');
              window.dispatchEvent(new CustomEvent('swUpdateActivated'));

              // Note: Removed automatic reload to prevent interrupting user work
              // The app should listen for 'swUpdateActivated' event and reload
              // at an appropriate time (e.g., when user is idle or clicks "Update")
            }
          });
        };

        registration.addEventListener('updatefound', updateFoundHandler);

        /**
         * Listen for service worker controller change
         * This fires when a new service worker takes control
         */
        controllerChangeHandler = () => {
          console.log('[SW Registration] Controller changed, new SW is active');
        };
        navigator.serviceWorker.addEventListener('controllerchange', controllerChangeHandler);

        /**
         * Check for updates periodically (every hour)
         * This ensures users get updates even if they keep the app open
         */
        updateInterval = setInterval(
          () => {
            console.log('[SW Registration] Checking for updates...');
            registration.update();
          },
          60 * 60 * 1000
        ); // 1 hour

        // Store cleanup function for this registration
        return () => {
          registration.removeEventListener('updatefound', updateFoundHandler);
        };
      } catch (error) {
        console.error('[SW Registration] Failed:', error);

        // Log specific error types for debugging
        if (error instanceof TypeError) {
          console.error('[SW Registration] Network error - check sw.js exists');
        } else if (error instanceof Error) {
          console.error('[SW Registration] Error message:', error.message);
        }
        return () => {}; // Return empty cleanup function on error
      }
    }

    let registrationCleanup: (() => void) | null = null;
    let isMounted = true;

    // Register on window load for better performance
    // This prevents service worker registration from competing with initial page load
    const loadHandler = async () => {
      const cleanup = await registerServiceWorker();
      // Only assign cleanup if component is still mounted
      if (isMounted) {
        registrationCleanup = cleanup;
      }
    };

    if (document.readyState === 'complete') {
      registerServiceWorker().then(cleanup => {
        // Only assign cleanup if component is still mounted
        if (isMounted) {
          registrationCleanup = cleanup;
        }
      });
    } else {
      window.addEventListener('load', loadHandler);
    }

    // Cleanup function
    return () => {
      isMounted = false;
      window.removeEventListener('load', loadHandler);
      if (updateInterval) {
        clearInterval(updateInterval);
      }
      if (controllerChangeHandler) {
        navigator.serviceWorker.removeEventListener('controllerchange', controllerChangeHandler);
      }
      if (registrationCleanup) {
        registrationCleanup();
      }
    };
  }, []);

  return null;
}
