import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { MarketingLegalPage } from '../../../components/MarketingLegalPage';
import { getDictionary } from '@/lib/i18n/dictionaries';
import { defaultLocale, locales, type Locale } from '@/lib/i18n/config';

interface LocaleTermsPageProps {
  params: Promise<{ locale: string }>;
}

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: LocaleTermsPageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    return {};
  }

  const dictionary = getDictionary(locale as Locale);
  const url = locale === defaultLocale ? 'https://tidex.no/terms' : `https://tidex.no/${locale}/terms`;

  return {
    title: dictionary.legal.terms.meta.title,
    description: dictionary.legal.terms.meta.description,
    openGraph: {
      title: dictionary.legal.terms.meta.title,
      description: dictionary.legal.terms.meta.description,
      url,
      type: 'website',
    },
  };
}

export default async function LocaleTermsPage({ params }: LocaleTermsPageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  const dictionary = getDictionary(locale as Locale);

  return (
    <MarketingLegalPage
      locale={locale as Locale}
      dictionary={dictionary}
      variant="terms"
      path="/terms"
    />
  );
}
