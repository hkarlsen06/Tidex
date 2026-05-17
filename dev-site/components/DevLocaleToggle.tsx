'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { devLocales, devLocaleNames, defaultDevLocale, type DevLocale } from '../lib/i18n-config';
import { buildLocalizedDevPath } from '../lib/paths';

interface DevLocaleToggleProps {
  currentLocale: DevLocale;
}

export function DevLocaleToggle({ currentLocale }: DevLocaleToggleProps) {
  const pathname = usePathname();

  // Strip any locale prefix to get the raw path
  let rawPath = pathname;
  for (const loc of devLocales) {
    const prefix = `/${loc}`;
    if (pathname === prefix || pathname.startsWith(`${prefix}/`)) {
      rawPath = pathname.slice(prefix.length) || '/';
      break;
    }
  }

  return (
    <div className="inline-flex items-center gap-1 rounded-full border border-white/6 bg-white/[0.015] p-[0.2rem] text-sm font-medium text-text-secondary backdrop-blur-sm">
      {devLocales.map((locale) => {
        const isActive = locale === currentLocale;
        const href = buildLocalizedDevPath(locale, rawPath);

        return (
          <Link
            key={locale}
            href={href}
            aria-current={isActive ? 'page' : undefined}
            className={`rounded-full px-3 py-1 transition-colors ${
              isActive
                ? 'bg-white/[0.05] text-text-secondary'
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
