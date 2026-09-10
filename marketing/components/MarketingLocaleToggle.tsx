import { localeNames, locales, type Locale } from '@/lib/i18n/config';
import { buildLocalizedMarketingPath } from '@/lib/paths';

interface MarketingLocaleToggleProps {
  locale: Locale;
  path?: string;
}

export function MarketingLocaleToggle({ locale, path }: MarketingLocaleToggleProps) {
  return (
    <nav
      aria-label="Language"
      className="inline-flex shrink-0 items-center rounded-full border border-white/6 bg-white/[0.015] p-[0.2rem] text-[0.95rem] font-medium text-text-muted backdrop-blur-sm"
    >
      {locales.map((item) => (
        <a
          key={item}
          href={buildLocalizedMarketingPath(item, path)}
          hrefLang={item}
          aria-current={item === locale ? 'page' : undefined}
          className={`inline-flex items-center rounded-full px-3.5 py-1.25 transition-colors hover:text-text-secondary ${
            item === locale ? 'bg-white/[0.04] text-text-secondary' : 'hover:bg-white/[0.02]'
          }`}
        >
          {localeNames[item]}
        </a>
      ))}
    </nav>
  );
}
