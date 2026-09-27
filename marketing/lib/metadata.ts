import type { Metadata } from 'next';
import type { Locale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import socialPreviewEn from '@/public/og/landing-en.png';
import socialPreviewNo from '@/public/og/landing-no.png';

interface LocalizedPageMetadata {
  title: string;
  description: string;
  ogTitle?: string;
  ogDescription?: string;
}

// `path` is the locale-independent page path without a trailing slash, for
// example '' for the landing page or '/privacy'.
export function localizedPageMetadata(
  locale: Locale,
  path: string,
  { title, description, ogTitle = title, ogDescription = description }: LocalizedPageMetadata
): Metadata {
  const url = `/${locale}${path}/`;
  const image = locale === 'no' ? socialPreviewNo : socialPreviewEn;
  const imageAlt = getMarketingDictionary(locale).marketing.meta.ogImageAlt;

  return {
    title,
    description,
    alternates: {
      canonical: url,
      languages: {
        no: `/no${path}/`,
        en: `/en${path}/`,
        'x-default': `${path}/`,
      },
    },
    openGraph: {
      title: ogTitle,
      description: ogDescription,
      url,
      type: 'website',
      images: [{ url: image.src, width: image.width, height: image.height, alt: imageAlt }],
    },
    twitter: {
      card: 'summary_large_image',
      title: ogTitle,
      description: ogDescription,
      images: [image.src],
    },
  };
}
