import type { Metadata } from 'next';
import { defaultLocale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { MarketingLegalPage } from '../../components/MarketingLegalPage';

const dictionary = getMarketingDictionary(defaultLocale);

export const metadata: Metadata = {
  title: dictionary.legal.security.meta.title,
  description: dictionary.legal.security.meta.description,
  openGraph: {
    title: dictionary.legal.security.meta.title,
    description: dictionary.legal.security.meta.description,
    url: 'https://tidex.no/security',
    type: 'website',
  },
};

export default function SecurityPage() {
  return (
    <MarketingLegalPage
      locale={defaultLocale}
      dictionary={dictionary}
      variant="security"
      path="/security"
    />
  );
}
