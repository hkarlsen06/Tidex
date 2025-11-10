'use client';

import { useState, useEffect } from 'react';
import { cn } from '@/lib/utils';

/**
 * SplashScreen component
 * Shows a loading screen on initial app launch (cold start only)
 * Does not show on route transitions
 */
export default function SplashScreen() {
  const [isVisible, setIsVisible] = useState(true);
  const [shouldRender, setShouldRender] = useState(true);

  useEffect(() => {
    // Check if this is a cold start or a navigation
    const isColdStart = !window.sessionStorage.getItem('app-hydrated');

    if (!isColdStart) {
      // Not a cold start, don't show splash
      // Schedule state update to avoid synchronous setState in effect
      Promise.resolve().then(() => setShouldRender(false));
      return;
    }

    // Mark as hydrated so splash doesn't show on subsequent navigations
    window.sessionStorage.setItem('app-hydrated', 'true');

    // Hide splash after a short delay or when app is ready
    const minDisplayTime = 800; // Minimum time to show splash (prevents flash)
    const maxDisplayTime = 2000; // Maximum time to show splash

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
    >
      {/* Logo */}
      <div className="mb-8 flex h-20 w-20 items-center justify-center rounded-2xl bg-surface-secondary shadow-lg">
        <span className="text-4xl font-bold text-brand-gradientStart">T</span>
      </div>

      {/* App name */}
      <h1 className="mb-6 text-2xl font-bold text-text-primary">Tidex</h1>

      {/* Loading spinner */}
      <div className="relative h-8 w-8">
        <div className="absolute inset-0 animate-spin rounded-full border-4 border-surface-secondary border-t-brand-gradientStart" />
      </div>

      {/* Loading text */}
      <p className="mt-4 text-sm text-text-secondary">Laster...</p>
    </div>
  );
}
