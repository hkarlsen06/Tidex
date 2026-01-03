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
  const currentLocale = pathname.split("/")[1] as Locale;

  // Build the new path with the target locale
  const buildLocalePath = (locale: Locale) => {
    // Create regex from locales array to stay in sync with config
    const localePattern = new RegExp(`^/(${locales.join("|")})`);
    const pathWithoutLocale = pathname.replace(localePattern, "");
    return `/${locale}${pathWithoutLocale || ""}`;
  };

  return (
    <div className="inline-flex items-center gap-1 rounded-lg border border-border-subtle bg-surface-primary p-1 text-sm font-medium">
      {locales.map((locale) => {
        const isActive = locale === currentLocale;
        const href = buildLocalePath(locale);

        return (
          <Link
            key={locale}
            href={href}
            aria-current={isActive ? "page" : undefined}
            className={`rounded-md px-3 py-1.5 transition-colors ${
              isActive
                ? "bg-brand-gradient-start text-text-inverse"
                : "text-text-muted hover:text-text-primary hover:bg-surface-secondary"
            }`}
          >
            {localeNames[locale]}
          </Link>
        );
      })}
    </div>
  );
}
