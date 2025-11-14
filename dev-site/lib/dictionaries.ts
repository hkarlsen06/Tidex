import type { DevLocale } from './i18n-config';
import { devNo } from '@/lib/i18n/dictionaries/dev.no';
import { devEn } from '@/lib/i18n/dictionaries/dev.en';

export type DevDictionary = typeof devNo;

const devDictionaries: Record<DevLocale, DevDictionary> = {
  no: devNo,
  en: devEn,
};

export function getDevDictionary(locale: DevLocale): DevDictionary {
  return devDictionaries[locale] ?? devDictionaries.no;
}
