/**
 * i18n exports
 */

export { locales, defaultLocale, localeNames, LOCALE_COOKIE, type Locale } from './config';
export {
  getDictionary,
  getAppDictionary,
  getAppShellDictionary,
  getMarketingDictionary,
  getAuthDictionary,
  APP_NAMESPACES,
  type AppNamespace,
} from './dictionaries';
export { getTranslations, setLocale } from './server';
export { useTranslations, useLocale, I18nContext } from './client';
export type { Dictionary } from './dictionaries/no';
