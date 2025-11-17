/**
 * Server-side i18n utilities
 *
 * Use in Server Components and Server Actions
 * With [locale] routing, locale comes from URL params, not cookies
 */

import { cookies } from 'next/headers';
import { type Locale, LOCALE_COOKIE } from './config';
import { getAppDictionary, type AppNamespace } from './dictionaries';

/**
 * Get translations for a specific locale
 * Use this in Server Components within [locale] routes
 *
 * @param locale - The locale from route params
 * @param namespaces - Namespaces required for the current route (app shell is always included)
 */
export function getTranslations(locale: Locale, namespaces: AppNamespace[] = []) {
  return getAppDictionary(locale, namespaces);
}

/**
 * Set the locale cookie
 * Use in Server Actions to persist language preference
 * (Note: With [locale] routing, navigation changes the URL, not just the cookie)
 */
export async function setLocale(locale: Locale) {
  const cookieStore = await cookies();
  cookieStore.set(LOCALE_COOKIE, locale, {
    path: '/',
    sameSite: 'lax',
    maxAge: 60 * 60 * 24 * 365, // 1 year
  });
}
