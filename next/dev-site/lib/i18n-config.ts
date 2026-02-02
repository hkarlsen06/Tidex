export const devLocales = ['no', 'en'] as const;
export type DevLocale = (typeof devLocales)[number];

export const defaultDevLocale: DevLocale = 'no';

export const devLocaleNames: Record<DevLocale, string> = {
  no: 'NO',
  en: 'EN',
};
