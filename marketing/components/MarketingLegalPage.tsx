import type { ReactNode } from 'react';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries';
import { TermsOfService } from '@/components/legal/TermsOfService';
import { PrivacyPolicy } from '@/components/legal/PrivacyPolicy';
import { SecurityPolicy } from '@/components/legal/SecurityPolicy';
import { MarketingLocaleToggle } from './MarketingLocaleToggle';
import { LocaleLangSetter } from './LocaleLangSetter';

interface MarketingLegalPageProps {
  locale: Locale;
  dictionary: Pick<Dictionary, 'marketing' | 'legal'>;
  variant: 'terms' | 'privacy' | 'security';
}

export function MarketingLegalPage({ locale, dictionary, variant }: MarketingLegalPageProps) {
  let content: ReactNode;
  const localeSwitcher = <MarketingLocaleToggle />;

  switch (variant) {
    case 'terms':
      content = <TermsOfService content={dictionary.legal.terms} headerAction={localeSwitcher} />;
      break;
    case 'privacy':
      content = <PrivacyPolicy content={dictionary.legal.privacy} headerAction={localeSwitcher} />;
      break;
    case 'security':
      content = <SecurityPolicy content={dictionary.legal.security} headerAction={localeSwitcher} />;
      break;
  }

  return (
    <div className="min-h-screen bg-background">
      <LocaleLangSetter locale={locale} />
      <div className="container mx-auto max-w-4xl px-4 py-12">
        {content}
      </div>
    </div>
  );
}
