import Link from 'next/link';
import { locales, localeNames, type Locale } from '@/lib/i18n/config';
import { buildLocalizedMarketingPath } from '../lib/paths';

interface MarketingLocaleToggleProps {
  currentLocale: Locale;
  path?: string;
}

export function MarketingLocaleToggle({ currentLocale, path = '' }: MarketingLocaleToggleProps) {
  return (
    <div className="inline-flex items-center gap-2 rounded-full bg-surface-primary/70 p-1 text-sm font-medium text-text-secondary shadow-app">
      {locales.map((locale) => {
        const isActive = locale === currentLocale;
        const href = buildLocalizedMarketingPath(locale, path);

        return (
          <Link
            key={locale}
            href={href}
            aria-current={isActive ? 'page' : undefined}
            className={`rounded-full px-3 py-1 transition-colors ${
              isActive
                ? 'bg-brand-gradient-mid/90 text-text-inverse'
                : 'text-text-secondary hover:text-text-primary'
            }`}
          >
            {localeNames[locale]}
          </Link>
        );
      })}
    </div>
  );
}
