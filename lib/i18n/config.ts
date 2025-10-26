/**
 * i18n Configuration
 *
 * Defines supported locales and default locale for the application.
 * Follows Next.js 16 patterns with cookie-based locale persistence.
 */

export const locales = ['no', 'en', 'de'] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = 'no';

export const localeNames: Record<Locale, string> = {
  no: 'Norsk',
  en: 'English',
  de: 'Deutsch',
};

export const LOCALE_COOKIE = 'tidex-locale';
