import type { Metadata } from 'next';
import { defaultLocale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { LandingPage } from '../components/LandingPage';

const dictionary = getMarketingDictionary(defaultLocale);

export const metadata: Metadata = {
  title: dictionary.marketing.meta.title,
  description: dictionary.marketing.meta.description,
  openGraph: {
    title: dictionary.marketing.meta.ogTitle,
    description: dictionary.marketing.meta.ogDescription,
    url: 'https://tidex.no',
    type: 'website',
    images: [
      {
        url: '/og/landing.png',
        width: 1200,
        height: 630,
        alt: dictionary.marketing.meta.ogImageAlt,
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: dictionary.marketing.meta.title,
    description: dictionary.marketing.meta.description,
    images: ['/og/landing.png'],
  },
};

export default function Page() {
  return <LandingPage locale={defaultLocale} dictionary={dictionary} path="" />;
}
