import { defaultDevLocale, type DevLocale } from './i18n-config';

export function buildLocalizedDevPath(locale: DevLocale, path = '') {
  const normalizedPath = path ? (path.startsWith('/') ? path : `/${path}`) : '';
  const sanitizedPath = normalizedPath === '/' ? '' : normalizedPath;

  if (locale === defaultDevLocale) {
    return sanitizedPath || '/';
  }

  return sanitizedPath ? `/${locale}${sanitizedPath}` : `/${locale}`;
}
