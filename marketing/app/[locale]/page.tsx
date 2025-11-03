import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { LandingPage } from '../../components/LandingPage';
import { getDictionary } from '@/lib/i18n/dictionaries';
import { defaultLocale, locales, type Locale } from '@/lib/i18n/config';

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

  const dictionary = getDictionary(locale as Locale);
  const url = locale === defaultLocale ? 'https://tidex.no' : `https://tidex.no/${locale}`;

  // Build language alternates for hreflang tags
  const languages: Record<string, string> = {};
  locales.forEach((loc) => {
    languages[loc] = `https://tidex.no/${loc}`;
  });

  return {
    title: dictionary.marketing.meta.title,
    description: dictionary.marketing.meta.description,
    alternates: {
      canonical: url,
      languages,
    },
    openGraph: {
      title: dictionary.marketing.meta.ogTitle,
      description: dictionary.marketing.meta.ogDescription,
      url,
      type: 'website',
      locale: locale,
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

  const dictionary = getDictionary(locale as Locale);

  return <LandingPage locale={locale as Locale} dictionary={dictionary} path="" />;
}
