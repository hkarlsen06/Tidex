import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { MarketingLegalPage } from '../../../components/MarketingLegalPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { defaultLocale, locales, type Locale } from '@/lib/i18n/config';

interface LocaleSecurityPageProps {
  params: Promise<{ locale: string }>;
}

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: LocaleSecurityPageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    return {};
  }

  const dictionary = getMarketingDictionary(locale as Locale);
  const url = locale === defaultLocale ? 'https://tidex.no/security' : `https://tidex.no/${locale}/security`;

  return {
    title: dictionary.legal.security.meta.title,
    description: dictionary.legal.security.meta.description,
    openGraph: {
      title: dictionary.legal.security.meta.title,
      description: dictionary.legal.security.meta.description,
      url,
      type: 'website',
    },
  };
}

export default async function LocaleSecurityPage({ params }: LocaleSecurityPageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  const dictionary = getMarketingDictionary(locale as Locale);

  return (
    <MarketingLegalPage
      locale={locale as Locale}
      dictionary={dictionary}
      variant="security"
      path="/security"
    />
  );
}
