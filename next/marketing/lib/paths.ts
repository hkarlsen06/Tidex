import { defaultLocale, type Locale } from '@/lib/i18n/config';

export function buildLocalizedMarketingPath(locale: Locale, path = '') {
  const normalizedPath = path ? (path.startsWith('/') ? path : `/${path}`) : '';
  const sanitizedPath = normalizedPath === '/' ? '' : normalizedPath;

  if (locale === defaultLocale) {
    return sanitizedPath || '/';
  }

  return `/${locale}${sanitizedPath}` || `/${locale}`;
}
