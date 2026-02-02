import type { Metadata } from 'next';
import { defaultLocale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { MarketingLegalPage } from '../../components/MarketingLegalPage';

const dictionary = getMarketingDictionary(defaultLocale);

export const metadata: Metadata = {
  title: dictionary.legal.terms.meta.title,
  description: dictionary.legal.terms.meta.description,
  openGraph: {
    title: dictionary.legal.terms.meta.title,
    description: dictionary.legal.terms.meta.description,
    url: 'https://tidex.no/terms',
    type: 'website',
  },
};

export default function TermsPage() {
  return (
    <MarketingLegalPage
      locale={defaultLocale}
      dictionary={dictionary}
      variant="terms"
      path="/terms"
    />
  );
}
