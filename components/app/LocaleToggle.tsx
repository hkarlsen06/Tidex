"use client";

import { usePathname, useRouter } from "next/navigation";
import { useTransition } from "react";
import { cn } from "@/lib/utils";
import type { Locale } from "@/lib/i18n/config";

const locales: { code: Locale; flag: string; label: string }[] = [
  { code: "no", flag: "🇳🇴", label: "NO" },
  { code: "en", flag: "🇬🇧", label: "EN" },
];

export function LocaleToggle() {
  const router = useRouter();
  const pathname = usePathname();
  const [isPending, startTransition] = useTransition();

  // Extract current locale directly from pathname
  const currentLocale = pathname.split('/')[1] as Locale;

  const switchLocale = async (newLocale: Locale) => {
    if (newLocale === currentLocale || isPending) return;

    try {
      // Update locale cookie via API route
      await fetch('/api/locale', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ locale: newLocale }),
      });

      // Navigate to the same route but with the new locale
      // Remove the current locale from pathname and add the new one
      const pathWithoutLocale = pathname.replace(/^\/(no|en)/, '');
      const newPath = `/${newLocale}${pathWithoutLocale || ""}`;

      startTransition(() => {
        router.push(newPath);
        router.refresh();
      });
    } catch (error) {
      console.error("Failed to update locale:", error);
    }
  };

  return (
    <div className="px-3 py-2.5" role="menuitem">
      <div className="flex rounded-lg overflow-hidden border border-border/40 bg-background">
        {locales.map((loc, index) => (
          <div key={loc.code} className="flex flex-1">
            <button
              type="button"
              onClick={() => switchLocale(loc.code)}
              disabled={isPending}
              className={cn(
                "flex-1 flex flex-col items-center justify-center gap-1 py-2.5 transition-colors",
                "disabled:opacity-50 disabled:cursor-not-allowed",
                currentLocale === loc.code
                  ? "bg-brand-primary text-white"
                  : "text-text-secondary hover:bg-accent hover:text-text-primary"
              )}
              aria-label={`Switch to ${loc.label}`}
              aria-pressed={currentLocale === loc.code}
            >
              <span className="text-lg leading-none">{loc.flag}</span>
              <span className="text-xs font-medium leading-none">{loc.label}</span>
            </button>
            {index < locales.length - 1 && (
              <div className="w-px bg-border/40" />
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
