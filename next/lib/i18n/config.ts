/**
 * i18n Configuration
 *
 * Defines supported locales and default locale for the application.
 * Follows Next.js 16 patterns with cookie-based locale persistence.
 */

export const locales = ['no', 'en'] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = 'no';

export const localeNames: Record<Locale, string> = {
  no: 'Norsk',
  en: 'English',
};

/**
 * Map app locales to Cloudflare Turnstile language codes.
 * Norwegian uses 'nb' (Bokmål) in Turnstile.
 * @see https://developers.cloudflare.com/turnstile/reference/supported-languages/
 */
export const turnstileLanguages: Record<Locale, string> = {
  no: 'nb', // Norwegian Bokmål
  en: 'en',
};

export const LOCALE_COOKIE = 'tidex-locale';
