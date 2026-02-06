'use client';

import { ExternalLink } from 'lucide-react';
import { useTranslations } from '@/lib/i18n/client';

function openExternalUrl(url: string) {
  window.open(url, '_blank', 'noopener,noreferrer');
}

interface LegalLinksProps {
  className?: string;
}

export function LegalLinks({ className }: LegalLinksProps) {
  const { t, locale } = useTranslations();

  const handleTermsClick = () => {
    openExternalUrl(`https://tidex.no/${locale}/terms`);
  };

  const handlePrivacyClick = () => {
    openExternalUrl(`https://tidex.no/${locale}/privacy`);
  };

  return (
    <div className={className ?? "pt-4 border-t border-border-subtle"}>
      <div className="flex flex-wrap gap-x-4 gap-y-2 text-sm">
        <button
          onClick={handleTermsClick}
          className="inline-flex items-center gap-1.5 text-text-secondary hover:text-text-primary transition-colors"
        >
          {t.footer.legal.terms}
          <ExternalLink className="h-3.5 w-3.5" />
        </button>
        <button
          onClick={handlePrivacyClick}
          className="inline-flex items-center gap-1.5 text-text-secondary hover:text-text-primary transition-colors"
        >
          {t.footer.legal.privacy}
          <ExternalLink className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );
}
