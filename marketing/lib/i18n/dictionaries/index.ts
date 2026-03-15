import type { Locale } from '../config';
import { legalEn } from './legal.en';
import { legalNo } from './legal.no';
import { marketingEn } from './marketing.en';
import { marketingNo } from './marketing.no';

const dictionaries = {
  no: {
    marketing: marketingNo,
    legal: legalNo,
  },
  en: {
    marketing: marketingEn,
    legal: legalEn,
  },
} as const satisfies Record<
  Locale,
  {
    marketing: typeof marketingNo | typeof marketingEn;
    legal: typeof legalNo | typeof legalEn;
  }
>;

export type Dictionary = (typeof dictionaries)[Locale];

export function getMarketingDictionary(locale: Locale): Dictionary {
  return dictionaries[locale] ?? dictionaries.no;
}
