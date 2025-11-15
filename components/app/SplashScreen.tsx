'use client';

import { useState, useEffect } from 'react';
import { cn } from '@/lib/utils';

/**
 * SplashScreen component - Optimized for performance
 * Shows a loading screen on initial app launch (cold start only)
 * Does not show on route transitions or block FCP
 */
export default function SplashScreen() {
  // Start hidden to not block FCP, show only if cold start
  const [isVisible, setIsVisible] = useState(false);
  const [shouldRender, setShouldRender] = useState(false);

  useEffect(() => {
    // Check if this is a cold start or a navigation
    const isColdStart = !window.sessionStorage.getItem('app-hydrated');

    if (!isColdStart) {
      // Not a cold start, don't show splash at all
      return;
    }

    // Show splash immediately (we're in cold start)
    setShouldRender(true);
    // Use requestAnimationFrame to ensure DOM is ready before fading in
    requestAnimationFrame(() => {
      setIsVisible(true);
    });

    // Mark as hydrated so splash doesn't show on subsequent navigations
    window.sessionStorage.setItem('app-hydrated', 'true');

    // Hide splash after a short delay
    const minDisplayTime = 600; // Reduced from 800ms
    const maxDisplayTime = 1500; // Reduced from 2000ms

    const startTime = Date.now();

    // Wait for document to be fully loaded
    const hideSpash = () => {
      const elapsed = Date.now() - startTime;
      const remainingTime = Math.max(0, minDisplayTime - elapsed);

      setTimeout(() => {
        setIsVisible(false);
        // Remove from DOM after fade out animation
        setTimeout(() => {
          setShouldRender(false);
        }, 300); // Match CSS transition duration
      }, remainingTime);
    };

    if (document.readyState === 'complete') {
      hideSpash();
    } else {
      window.addEventListener('load', hideSpash);
      // Fallback: hide after max time even if load event doesn't fire
      const fallbackTimer = setTimeout(hideSpash, maxDisplayTime);

      return () => {
        window.removeEventListener('load', hideSpash);
        clearTimeout(fallbackTimer);
      };
    }
  }, []);

  if (!shouldRender) {
    return null;
  }

  return (
    <div
      className={cn(
        'fixed inset-0 z-[9999] flex flex-col items-center justify-center',
        'bg-background transition-opacity duration-300',
        isVisible ? 'opacity-100' : 'opacity-0 pointer-events-none'
      )}
      aria-hidden="true"
    >
      {/* Logo - Simplified for faster paint */}
      <div className="mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-surface-secondary">
        <span className="text-3xl font-bold text-brand-gradientStart">T</span>
      </div>

      {/* App name */}
      <h1 className="mb-4 text-xl font-bold text-text-primary">Tidex</h1>

      {/* Loading spinner - CSS only, no JS */}
      <div className="relative h-6 w-6">
        <div className="absolute inset-0 animate-spin rounded-full border-2 border-surface-secondary border-t-brand-gradientStart" />
      </div>
    </div>
  );
}
