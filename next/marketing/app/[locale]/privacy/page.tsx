import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { MarketingLegalPage } from '../../../components/MarketingLegalPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { defaultLocale, locales, type Locale } from '@/lib/i18n/config';

interface LocalePrivacyPageProps {
  params: Promise<{ locale: string }>;
}

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: LocalePrivacyPageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    return {};
  }

  const dictionary = getMarketingDictionary(locale as Locale);
  const url = locale === defaultLocale ? 'https://tidex.no/privacy' : `https://tidex.no/${locale}/privacy`;

  return {
    title: dictionary.legal.privacy.meta.title,
    description: dictionary.legal.privacy.meta.description,
    openGraph: {
      title: dictionary.legal.privacy.meta.title,
      description: dictionary.legal.privacy.meta.description,
      url,
      type: 'website',
    },
  };
}

export default async function LocalePrivacyPage({ params }: LocalePrivacyPageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  const dictionary = getMarketingDictionary(locale as Locale);

  return (
    <MarketingLegalPage
      locale={locale as Locale}
      dictionary={dictionary}
      variant="privacy"
      path="/privacy"
    />
  );
}
