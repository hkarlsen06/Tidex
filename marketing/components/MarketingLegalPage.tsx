import type { ReactNode } from 'react';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { TermsOfService } from '@components/legal/TermsOfService';
import { PrivacyPolicy } from '@components/legal/PrivacyPolicy';
import { MarketingLocaleToggle } from './MarketingLocaleToggle';
import { LocaleLangSetter } from './LocaleLangSetter';

interface MarketingLegalPageProps {
  locale: Locale;
  dictionary: Pick<Dictionary, 'marketing' | 'legal'>;
  variant: 'terms' | 'privacy';
  path: '/terms' | '/privacy';
}

export function MarketingLegalPage({ locale, dictionary, variant, path }: MarketingLegalPageProps) {
  const content: ReactNode =
    variant === 'terms' ? (
      <TermsOfService content={dictionary.legal.terms} />
    ) : (
      <PrivacyPolicy content={dictionary.legal.privacy} />
    );

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
