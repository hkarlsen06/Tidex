/**
 * Language Switcher Component
 *
 * Allows users to switch between supported languages
 * Navigates to the new locale URL
 */

'use client';

import { usePathname, useRouter } from 'next/navigation';
import { useTranslations } from '@/lib/i18n/client';
import { locales, localeNames, type Locale } from '@/lib/i18n/config';
import { Button } from '@/components/app/Button';

export function LanguageSwitcher() {
  const { locale, setLocale } = useTranslations();
  const pathname = usePathname();
  const router = useRouter();

  const handleLocaleChange = (newLocale: Locale) => {
    if (newLocale === locale) return;

    // Replace the current locale in the pathname with the new one
    const segments = pathname.split('/');
    segments[1] = newLocale; // Replace locale segment
    const newPath = segments.join('/');

    // Update cookie via context (which calls API)
    setLocale(newLocale);

    // Navigate to new locale path
    router.push(newPath);
  };

  return (
    <div className="flex gap-2">
      {locales.map((loc) => (
        <Button
          key={loc}
          variant={locale === loc ? 'default' : 'outline'}
          size="sm"
          onClick={() => handleLocaleChange(loc)}
        >
          {localeNames[loc]}
        </Button>
      ))}
    </div>
  );
}
