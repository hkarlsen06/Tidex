'use client';

import { useEffect } from 'react';
import type { DevLocale } from '../lib/i18n-config';

interface LocaleLangSetterProps {
  locale: DevLocale;
}

export function LocaleLangSetter({ locale }: LocaleLangSetterProps) {
  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  return null;
}
