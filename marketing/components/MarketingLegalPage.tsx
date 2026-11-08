import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries';
import { LegalDocument } from '@/components/legal/LegalDocument';
import { MarketingLocaleToggle } from './MarketingLocaleToggle';
import { MarketingHomeLink } from './MarketingHomeLink';

interface MarketingLegalPageProps {
  locale: Locale;
  dictionary: Pick<Dictionary, 'marketing' | 'legal'>;
  variant: 'terms' | 'privacy' | 'security';
}

export function MarketingLegalPage({ locale, dictionary, variant }: MarketingLegalPageProps) {
  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto max-w-4xl px-4 py-12">
        <div className="mb-8">
          <MarketingHomeLink locale={locale} />
        </div>
        <LegalDocument
          content={dictionary.legal[variant]}
          headerAction={<MarketingLocaleToggle locale={locale} path={`/${variant}`} />}
        />
      </div>
    </div>
  );
}
