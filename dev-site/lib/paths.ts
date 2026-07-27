import { defaultDevLocale, devLocales, type DevLocale } from './i18n-config';

/**
 * Turns any pathname into its locale-free route, e.g. `/no/projects/` -> `/projects`.
 * The default locale is served from both `/` and `/no`, so comparing raw pathnames
 * against built hrefs does not work.
 */
export function stripDevLocalePrefix(pathname: string) {
  const withoutTrailingSlash = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;

  for (const locale of devLocales) {
    const prefix = `/${locale}`;
    if (withoutTrailingSlash === prefix) return '/';
    if (withoutTrailingSlash.startsWith(`${prefix}/`)) return withoutTrailingSlash.slice(prefix.length);
  }

  return withoutTrailingSlash || '/';
}

export function buildLocalizedDevPath(locale: DevLocale, path = '') {
  const normalizedPath = path ? (path.startsWith('/') ? path : `/${path}`) : '';
  const sanitizedPath = normalizedPath === '/' ? '' : normalizedPath;

  if (locale === defaultDevLocale) {
    return sanitizedPath || '/';
  }

  return sanitizedPath ? `/${locale}${sanitizedPath}` : `/${locale}`;
}
