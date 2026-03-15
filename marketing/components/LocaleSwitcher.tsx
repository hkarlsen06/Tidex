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
    <div className="inline-flex items-center gap-0.5 rounded-full bg-white/8 p-0.5 text-sm font-medium backdrop-blur-sm">
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
                ? "bg-surface-primary text-text-primary shadow-sm"
                : "text-text-muted hover:text-text-secondary"
            }`}
          >
            {localeNames[locale]}
          </Link>
        );
      })}
    </div>
  );
}
