/**
 * Client-side i18n utilities
 *
 * Use in Client Components via context
 */

'use client';

import { createContext, useContext } from 'react';
import type { Locale } from './config';
import type { Dictionary } from './dictionaries/no';

interface I18nContextValue {
  locale: Locale;
  t: Dictionary;
  setLocale: (locale: Locale) => void;
}

export const I18nContext = createContext<I18nContextValue | null>(null);

/**
 * Hook to access translations in Client Components
 * Must be used within I18nProvider
 */
export function useTranslations() {
  const context = useContext(I18nContext);
  if (!context) {
    throw new Error('useTranslations must be used within I18nProvider');
  }
  return context;
}

/**
 * Hook to access just the locale
 */
export function useLocale() {
  const context = useContext(I18nContext);
  if (!context) {
    throw new Error('useLocale must be used within I18nProvider');
  }
  return context.locale;
}
