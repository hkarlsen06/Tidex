"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { locales, localeNames, type Locale } from "@/lib/i18n/config";

/**
 * Client-side locale switcher with "Norsk" / "English" labels.
 * Can be used on any page - switches locale while preserving the current path.
 */
export function LocaleSwitcher() {
  const pathname = usePathname();

  // Extract current locale from pathname
  const pathLocale = pathname.split('/')[1] as Locale;
  const currentLocale = locales.includes(pathLocale) ? pathLocale : locales[0];

  // Build the new path with the target locale
  const buildLocalePath = (locale: Locale) => {
    // Create regex from locales array to stay in sync with config
    const localePattern = new RegExp(`^/(${locales.join("|")})`);
    const pathWithoutLocale = pathname.replace(localePattern, "");
    return `/${locale}${pathWithoutLocale || ""}`;
  };

  return (
    <div className="inline-flex items-center gap-1 rounded-full border border-white/10 bg-white/[0.03] p-1 text-sm font-medium text-text-secondary">
      {locales.map((locale) => {
        const isActive = locale === currentLocale;
        const href = buildLocalePath(locale);

        return (
          <Link
            key={locale}
            href={href}
            aria-current={isActive ? "page" : undefined}
            className={`rounded-full px-4 py-1.5 transition-all ${
              isActive
                ? "bg-white text-text-inverse"
                : "text-text-muted hover:bg-white/[0.04] hover:text-text-primary"
            }`}
          >
            {localeNames[locale]}
          </Link>
        );
      })}
    </div>
  );
}
