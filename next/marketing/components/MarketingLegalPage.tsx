import type { ReactNode } from 'react';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { TermsOfService } from '@components/legal/TermsOfService';
import { PrivacyPolicy } from '@components/legal/PrivacyPolicy';
import { SecurityPolicy } from '@components/legal/SecurityPolicy';
import { MarketingLocaleToggle } from './MarketingLocaleToggle';
import { LocaleLangSetter } from './LocaleLangSetter';

interface MarketingLegalPageProps {
  locale: Locale;
  dictionary: Pick<Dictionary, 'marketing' | 'legal'>;
  variant: 'terms' | 'privacy' | 'security';
  path: '/terms' | '/privacy' | '/security';
}

export function MarketingLegalPage({ locale, dictionary, variant, path }: MarketingLegalPageProps) {
  let content: ReactNode;

  switch (variant) {
    case 'terms':
      content = <TermsOfService content={dictionary.legal.terms} />;
      break;
    case 'privacy':
      content = <PrivacyPolicy content={dictionary.legal.privacy} />;
      break;
    case 'security':
      content = <SecurityPolicy content={dictionary.legal.security} />;
      break;
  }

  return (
    <div className="min-h-screen bg-background">
      <LocaleLangSetter locale={locale} />
      <div className="container mx-auto max-w-4xl px-4 py-12">
        <div className="mb-6 flex justify-end">
          <MarketingLocaleToggle currentLocale={locale} path={path} />
        </div>
        {content}
      </div>
    </div>
  );
}
