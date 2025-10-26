/**
 * I18n Provider
 *
 * Provides translations context to Client Components
 * Should be rendered in the root layout with server-fetched locale and dictionary
 */

'use client';

import { useState, useTransition, type ReactNode } from 'react';
import { useRouter } from 'next/navigation';
import { I18nContext } from '@/lib/i18n/client';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface I18nProviderProps {
  locale: Locale;
  dictionary: Dictionary;
  children: ReactNode;
}

export function I18nProvider({ locale: initialLocale, dictionary: initialDictionary, children }: I18nProviderProps) {
  const router = useRouter();
  const [_isPending, startTransition] = useTransition();
  const [locale, setLocaleState] = useState(initialLocale);
  const [dictionary, setDictionary] = useState(initialDictionary);

  const setLocale = (newLocale: Locale) => {
    startTransition(async () => {
      // Call server action to update cookie
      const response = await fetch('/api/locale', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ locale: newLocale }),
      });

      if (response.ok) {
        const data = await response.json();
        setLocaleState(newLocale);
        setDictionary(data.dictionary);
        router.refresh();
      }
    });
  };

  return (
    <I18nContext.Provider value={{ locale, t: dictionary, setLocale }}>
      {children}
    </I18nContext.Provider>
  );
}
