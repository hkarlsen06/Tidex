'use client';

import { useEffect } from 'react';
import type { Locale } from '@/lib/i18n/config';

interface LocaleLangSetterProps {
  locale: Locale;
}

export function LocaleLangSetter({ locale }: LocaleLangSetterProps) {
  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  return null;
}
