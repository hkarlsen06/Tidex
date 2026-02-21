import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { LandingPage } from '../../components/LandingPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { locales, type Locale } from '@/lib/i18n/config';

interface LocalePageProps {
  params: Promise<{ locale: string }>;
}

export async function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: LocalePageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    return {};
  }

  const dictionary = getMarketingDictionary(locale as Locale);
  const url = `https://tidex.no/${locale}`;

  return {
    title: dictionary.marketing.meta.title,
    description: dictionary.marketing.meta.description,
    openGraph: {
      title: dictionary.marketing.meta.ogTitle,
      description: dictionary.marketing.meta.ogDescription,
      url,
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
}

export default async function LocaleLandingPage({ params }: LocalePageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  const dictionary = getMarketingDictionary(locale as Locale);

  return <LandingPage locale={locale as Locale} dictionary={dictionary} />;
}
