'use client';

import { useEffect } from 'react';

const STORAGE_KEY = 'marketing:hero-initial-dvh';

const setCssVariable = (value: number) => {
  if (!Number.isFinite(value) || value <= 0) return;
  document.documentElement.style.setProperty('--hero-initial-dvh', `${value}px`);
};

const getViewportHeight = () => {
  const measured = window.visualViewport?.height ?? window.innerHeight;
  return Math.round(measured);
};

export default function ViewportHeightSetter() {
  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }

    const stored = window.localStorage.getItem(STORAGE_KEY);
    const storedValue = stored ? parseFloat(stored) : Number.NaN;
    if (Number.isFinite(storedValue) && storedValue > 0) {
      setCssVariable(storedValue);
    }

    const measured = getViewportHeight();
    if (measured > 0) {
      setCssVariable(measured);
      window.localStorage.setItem(STORAGE_KEY, String(measured));
    }
  }, []);

  return null;
}
