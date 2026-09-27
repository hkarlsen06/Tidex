import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { LandingPage } from '../../components/LandingPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { locales, type Locale } from '@/lib/i18n/config';
import { localizedPageMetadata } from '@/lib/metadata';

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

  const meta = getMarketingDictionary(locale as Locale).marketing.meta;

  return localizedPageMetadata(locale as Locale, '', meta);
}

export default async function LocaleLandingPage({ params }: LocalePageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  const dictionary = getMarketingDictionary(locale as Locale);

  return <LandingPage locale={locale as Locale} dictionary={dictionary} />;
}
