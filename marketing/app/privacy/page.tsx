import type { Metadata } from 'next';
import { defaultLocale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { MarketingLegalPage } from '../../components/MarketingLegalPage';

const dictionary = getMarketingDictionary(defaultLocale);

export const metadata: Metadata = {
  title: dictionary.legal.privacy.meta.title,
  description: dictionary.legal.privacy.meta.description,
  openGraph: {
    title: dictionary.legal.privacy.meta.title,
    description: dictionary.legal.privacy.meta.description,
    url: 'https://tidex.no/privacy',
    type: 'website',
  },
};

export default function PrivacyPage() {
  return (
    <MarketingLegalPage
      locale={defaultLocale}
      dictionary={dictionary}
      variant="privacy"
      path="/privacy"
    />
  );
}
