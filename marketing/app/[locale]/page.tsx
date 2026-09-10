import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { LandingPage } from '../../components/LandingPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { locales, type Locale } from '@/lib/i18n/config';
import socialPreviewEn from '@/public/og/landing-en.png';
import socialPreviewNo from '@/public/og/landing-no.png';

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
  const socialPreview = locale === 'no' ? socialPreviewNo : socialPreviewEn;
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
          url: socialPreview.src,
          width: socialPreview.width,
          height: socialPreview.height,
          alt: dictionary.marketing.meta.ogImageAlt,
        },
      ],
    },
    twitter: {
      card: 'summary_large_image',
      title: dictionary.marketing.meta.title,
      description: dictionary.marketing.meta.description,
      images: [socialPreview.src],
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
