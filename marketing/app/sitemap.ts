import type { MetadataRoute } from 'next';
import { locales } from '@/lib/i18n/config';

export const dynamic = 'force-static';

const localizedPaths = ['', '/support', '/privacy', '/terms', '/security'];

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    ...localizedPaths.flatMap((path) =>
      locales.map((locale) => ({ url: `https://tidex.no/${locale}${path}/` }))
    ),
    { url: 'https://tidex.no/docs/payroll/' },
  ];
}
