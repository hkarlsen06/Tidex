import Link from 'next/link';
import { devLocales, devLocaleNames, type DevLocale } from '../lib/i18n-config';
import { buildLocalizedDevPath } from '../lib/paths';

interface DevLocaleToggleProps {
  currentLocale: DevLocale;
  path?: string;
}

export function DevLocaleToggle({ currentLocale, path = '' }: DevLocaleToggleProps) {
  return (
    <div className="inline-flex items-center gap-2 rounded-full bg-surface-primary/70 p-1 text-sm font-medium text-text-secondary shadow-app">
      {devLocales.map((locale) => {
        const isActive = locale === currentLocale;
        const href = buildLocalizedDevPath(locale, path);

        return (
          <Link
            key={locale}
            href={href}
            aria-current={isActive ? 'page' : undefined}
            className={`rounded-full px-3 py-1 transition-colors ${
              isActive
                ? 'bg-brand-gradientMid/90 text-text-inverse'
                : 'text-text-secondary hover:text-text-primary'
            }`}
          >
            {devLocaleNames[locale]}
          </Link>
        );
      })}
    </div>
  );
}
